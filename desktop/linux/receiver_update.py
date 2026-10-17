"""Official portable-package updates. Importing this module has no side effects.

Downloads never run code or stop a receiver. A verified staged package is applied
only before the backend starts or after an explicit Update and Restart action.
"""

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import threading
import tarfile
import tempfile
import time
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

from autostart import atomic_text, config_home

API = "https://api.github.com/repos/chekusu/sofatap/releases"
MAX_ARCHIVE = 180 * 1024 * 1024
MAX_EXPANDED = 450 * 1024 * 1024
INTERVAL = 24 * 60 * 60


def version_key(value):
    match = re.fullmatch(r"(?:v)?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(alpha|beta|rc)\.(0|[1-9]\d*))?", value)
    if not match:
        raise ValueError("Unsupported release version")
    major, minor, patch, stage, number = match.groups()
    return int(major), int(minor), int(patch), {"alpha": 0, "beta": 1, "rc": 2, None: 3}[stage], int(number or 0)


@dataclass(frozen=True)
class Release:
    version: str
    runtime: str
    url: str
    size: int
    digest: str


def select_release(releases, current, runtime):
    if runtime not in ("linux-x64", "linux-arm64"):
        raise ValueError("Unsupported architecture")
    candidates = []
    asset_name = f"SofaTap-Linux-{runtime.removeprefix('linux-')}.tar.gz"
    for release in releases:
        tag = release.get("tag_name", "")
        if release.get("draft") or not tag.startswith("v"):
            continue
        try:
            newer = version_key(tag) > version_key(current)
        except (ValueError, TypeError):
            continue
        if not newer or ("-" not in current and (release.get("prerelease") or "-" in tag)):
            continue
        matching = [asset for asset in release.get("assets", []) if asset.get("name") == asset_name]
        if matching:
            candidates.append((version_key(tag), tag, matching))
    if not candidates:
        return None
    _, tag, assets = max(candidates, key=lambda row: row[0])
    if len(assets) != 1:
        raise ValueError("Duplicate update assets")
    asset = assets[0]
    expected = f"https://github.com/chekusu/sofatap/releases/download/{tag}/{asset_name}"
    digest, size = asset.get("digest", ""), asset.get("size", 0)
    if (asset.get("state") != "uploaded" or asset.get("browser_download_url") != expected
            or not isinstance(size, int) or not 0 < size <= MAX_ARCHIVE
            or not isinstance(digest, str) or not re.fullmatch(r"sha256:[a-f0-9]{64}", digest)):
        raise ValueError("Latest update has incomplete verification data")
    return Release(tag[1:], runtime, expected, size, digest[7:])


class SafeRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        parts = urlsplit(newurl)
        if (parts.scheme != "https" or parts.hostname not in
                ("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")
                or parts.username or parts.password or parts.port not in (None, 443)):
            raise ValueError("Unexpected update redirect")
        return super().redirect_request(request, fp, code, message, headers, newurl)


def open_url(url):
    return build_opener(SafeRedirect()).open(Request(url, headers={
        "User-Agent": "Sofatap-Receiver-Updater", "Accept": "application/vnd.github+json"}), timeout=30)


def fetch_releases():
    releases = []
    for page in range(1, 6):
        with open_url(f"{API}?per_page=100&page={page}") as response:
            payload = response.read(4 * 1024 * 1024 + 1)
        if len(payload) > 4 * 1024 * 1024:
            raise ValueError("Update catalog too large")
        batch = json.loads(payload)
        if not isinstance(batch, list):
            raise ValueError("Invalid update catalog")
        releases.extend(batch)
        if len(batch) < 100:
            return releases
    raise ValueError("Update catalog pagination limit reached")


def verify_archive(archive, release):
    digest = hashlib.sha256()
    count = 0
    with Path(archive).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            count += len(block)
            if count > release.size:
                raise ValueError("Update size mismatch")
            digest.update(block)
    if count != release.size or digest.hexdigest() != release.digest:
        raise ValueError("Update checksum mismatch")


def unpack(archive, release, destination):
    """No links, special files, path traversal, duplicate paths or permissions."""
    verify_archive(archive, release)
    prefix = f"SofaTap-Linux-{release.runtime.removeprefix('linux-')}"
    total, seen = 0, set()
    destination = Path(destination)
    with tarfile.open(archive, "r:gz") as bundle:
        for member in bundle:
            path = PurePosixPath(member.name)
            if (not member.name or path.is_absolute() or ".." in path.parts
                    or "\\" in member.name or not path.parts or path.parts[0] != prefix
                    or any(ord(c) < 32 for c in member.name)
                    or member.name in seen or len(seen) >= 4096
                    or not (member.isdir() or member.isfile())):
                raise ValueError("Unsafe update archive")
            seen.add(member.name)
            total += member.size
            if total > MAX_EXPANDED or member.size < 0:
                raise ValueError("Expanded update too large")
            target = destination.joinpath(*path.parts[1:])
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with bundle.extractfile(member) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(0o755 if member.mode & 0o111 else 0o644)
    manifest = json.loads((destination / "BUILD-MANIFEST.json").read_text())
    if manifest.get("updateVersion") != release.version or manifest.get("runtime") != release.runtime:
        raise ValueError("Update package version or architecture mismatch")
    for required in ("sofatap", "lib/SofaTapHost", "lib/linux/sofatap.py", "lib/linux/receiver_update.py"):
        if not (destination / required).is_file():
            raise ValueError("Incomplete update package")
    if not os.access(destination / "sofatap", os.X_OK) or not os.access(destination / "lib/SofaTapHost", os.X_OK):
        raise ValueError("Update executable is not executable")


class ReceiverUpdater:
    def __init__(self, package, settings=None, cache=None):
        self.package = Path(package).absolute()
        manifest = json.loads((self.package / "BUILD-MANIFEST.json").read_text())
        self.version = manifest["updateVersion"]
        self.runtime = manifest["runtime"]
        version_key(self.version)
        self.preference_lock = threading.RLock()
        self.settings = Path(settings) if settings else config_home() / "sofatap/updates.json"
        cache_home = os.environ.get("XDG_CACHE_HOME", "")
        base = Path(cache_home) if cache_home and Path(cache_home).is_absolute() else Path.home() / ".cache"
        self.cache = Path(cache) if cache else base / "sofatap/updates"
        # Bind a stage to this installation, not another portable copy/architecture.
        self.cache /= hashlib.sha256(str(self.package).encode()).hexdigest()[:16]

    def preferences(self):
        try:
            value = json.loads(self.settings.read_text())
            if not isinstance(value, dict) or type(value.get("automatic")) is not bool:
                raise ValueError("Invalid updater preferences")
            return value
        except FileNotFoundError:
            return {"automatic": True, "lastCheck": 0}

    def set_automatic(self, enabled):
        with self.preference_lock:
            value = self.preferences()
            value["automatic"] = bool(enabled)
            atomic_text(self.settings, json.dumps(value))

    def writable(self):
        return (self.package == self.package.resolve() and self.package.is_dir()
                and self.package.stat().st_uid == os.getuid()
                and os.access(self.package.parent, os.W_OK | os.X_OK)
                and os.access(self.package, os.W_OK | os.X_OK))

    def pending(self):
        try:
            release = Release(**json.loads((self.cache / "pending.json").read_text()))
            if release.runtime != self.runtime or version_key(release.version) <= version_key(self.version):
                return None
            # Validate stored metadata as strictly as a fresh API result.
            name = f"SofaTap-Linux-{self.runtime.removeprefix('linux-')}.tar.gz"
            expected = f"https://github.com/chekusu/sofatap/releases/download/v{release.version}/{name}"
            if (release.url != expected or not 0 < release.size <= MAX_ARCHIVE
                    or not re.fullmatch(r"[a-f0-9]{64}", release.digest)):
                return None
            return release
        except (OSError, ValueError, TypeError):
            return None

    def check(self, manual=False):
        with self.preference_lock:
            preferences = self.preferences()
            if not manual and (not preferences["automatic"] or time.time() - preferences.get("lastCheck", 0) < INTERVAL):
                return "已准备更新，重启后安装" if self.pending() else ""
            # Rate-limit failures as well as successes; manual checks remain available.
            preferences["lastCheck"] = time.time()
            atomic_text(self.settings, json.dumps(preferences))
        release = select_release(fetch_releases(), self.version, self.runtime)
        if release is None:
            return "当前已是最新版本"
        if not self.writable():
            return f"发现 {release.version}，安装目录不可写，请从 sofatap.app 下载更新"
        self.cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        if self.pending() == release:
            try:
                verify_archive(self.cache / "package.tar.gz", release)
                return f"{release.version} 已下载，下次启动自动安装"
            except (OSError, ValueError):
                pass
        temporary = self.cache / "download.part"
        try:
            count = 0
            with open_url(release.url) as response, temporary.open("wb") as output:
                while block := response.read(1024 * 1024):
                    count += len(block)
                    if count > release.size:
                        raise ValueError("Update size mismatch")
                    output.write(block)
            verify_archive(temporary, release)
            # Validate the whole archive before offering it to the user.
            with tempfile.TemporaryDirectory(prefix="verify-", dir=self.cache) as validation:
                unpack(temporary, release, validation)
            os.replace(temporary, self.cache / "package.tar.gz")
            atomic_text(self.cache / "pending.json", json.dumps(release.__dict__))
            return f"{release.version} 已下载，下次启动自动安装"
        finally:
            temporary.unlink(missing_ok=True)

    def preserve_unmanaged(self, stage):
        old = json.loads((self.package / "BUILD-MANIFEST.json").read_text())
        managed = old.get("files")
        if not isinstance(managed, dict):
            raise ValueError("Installed package has no file inventory; update manually")
        managed = set(managed) | {"BUILD-MANIFEST.json"}
        for source in self.package.rglob("*"):
            if source.is_symlink():
                raise ValueError("Installed package contains links; update manually")
            relative = source.relative_to(self.package)
            if source.is_file() and relative.as_posix() not in managed:
                target = stage / relative
                if target.exists():
                    raise ValueError("Update conflicts with a custom installation file")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
            elif not source.is_file() and not source.is_dir():
                raise ValueError("Installed package contains a special file")

    def validate_runtime(self, stage):
        # --help exits before opening a port, profile, GUI or input worker.
        result = subprocess.run([str(stage / "lib/SofaTapHost"), "--help"],
                                capture_output=True, timeout=20, check=False)
        if result.returncode != 0 or b"Sofatap receiver backend" not in result.stdout:
            raise ValueError("Update backend cannot start on this system")
        for source in (stage / "lib/linux").glob("*.py"):
            compile(source.read_bytes(), str(source), "exec")

    def apply_pending(self, explicit=False):
        if not explicit and not self.preferences()["automatic"]:
            return False
        release = self.pending()
        if not release or not self.writable():
            return False
        # Extract beside installation so both renames are on the same filesystem.
        stage = Path(tempfile.mkdtemp(prefix=".sofatap-update-", dir=self.package.parent))
        backup = self.package.with_name(self.package.name + ".backup-" + str(time.time_ns()))
        try:
            unpack(self.cache / "package.tar.gz", release, stage)
            self.validate_runtime(stage)
            self.preserve_unmanaged(stage)
            os.replace(self.package, backup)
            try:
                os.replace(stage, self.package)
            except BaseException:
                os.replace(backup, self.package)
                raise
            (self.cache / "pending.json").unlink(missing_ok=True)
            self.version = release.version
            return True
        finally:
            if stage.exists():
                shutil.rmtree(stage)
