#!/usr/bin/env python3
"""Inspect the actual built Mac App Store candidate; never launches it."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess


def run(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True, stderr=subprocess.DEVNULL).strip()


def signature(path: Path) -> dict:
    result = subprocess.run(["codesign", "-dvvv", str(path)], capture_output=True, text=True, check=True)
    properties = dict(line.split("=", 1) for line in result.stderr.splitlines() if "=" in line)
    entitlements = plistlib.loads(subprocess.check_output(
        ["codesign", "--display", "--entitlements", ":-", str(path)], stderr=subprocess.DEVNULL))
    flags = re.search(r"\bflags=0x([0-9a-fA-F]+)\b", result.stderr)
    if not flags or not (int(flags.group(1), 16) & 0x10000):
        raise SystemExit("Hardened Runtime is missing: " + str(path))
    return {"entitlements": entitlements, "adHoc": properties.get("Signature") == "adhoc"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve()
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.chekusu.sofatap.receiver":
        raise SystemExit("Unexpected receiver bundle identifier")
    launcher = contents / "MacOS" / info["CFBundleExecutable"]
    if set(run("lipo", "-archs", str(launcher)).split()) != {"arm64", "x86_64"}:
        raise SystemExit("The launcher must contain both Apple Silicon and Intel slices")
    signatures = {"application": signature(app)}
    expected_parent = {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.network.client": True,
        "com.apple.security.network.server": True,
    }
    for key, value in expected_parent.items():
        if signatures["application"]["entitlements"].get(key) != value:
            raise SystemExit("Missing application entitlement: " + key)
    expected_helper = {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.inherit": True,
        "com.apple.security.cs.allow-jit": True,
    }
    executable_hashes = {"launcher": hashlib.sha256(launcher.read_bytes()).hexdigest()}
    for architecture, macho in (("arm64", "arm64"), ("x64", "x86_64")):
        helper = contents / "Helpers" / architecture / "SofaTapHost"
        if run("lipo", "-archs", str(helper)) != macho:
            raise SystemExit("Helper architecture mismatch: " + architecture)
        signatures[architecture] = signature(helper)
        if signatures[architecture]["entitlements"] != expected_helper:
            raise SystemExit("Unexpected inheriting helper entitlements: " + architecture)
        executable_hashes[architecture] = hashlib.sha256(helper.read_bytes()).hexdigest()
        licenses = contents / "Resources/licenses" / ("osx-" + architecture) / "RESOLVED-PACKAGES.txt"
        if not licenses.is_file():
            raise SystemExit("Missing architecture-specific runtime licenses")
    for filename in ("SofaTap.icns", "LICENSE", "THIRD-PARTY-NOTICES.md", "PrivacyInfo.xcprivacy"):
        if not (contents / "Resources" / filename).is_file():
            raise SystemExit("Missing bundle resource: " + filename)
    prohibited = {"pairing.dat", "receiver.lock", "login-service.json", "service.dat"}
    for item in app.rglob("*"):
        if item.name in prohibited or item.suffix.lower() in {".pfx", ".p12", ".key", ".pem"}:
            raise SystemExit("Private or runtime state must not be bundled: " + item.name)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    root = Path(__file__).resolve().parents[2]
    manifest = {
        "builtAt": datetime.now(timezone.utc).isoformat(),
        "bundleIdentifier": info["CFBundleIdentifier"],
        "marketingVersion": info["CFBundleShortVersionString"],
        "buildNumber": info["CFBundleVersion"],
        "minimumMacOS": info["LSMinimumSystemVersion"],
        "sourceRevision": run("git", "-C", str(root), "rev-parse", "HEAD"),
        "sourceDirty": bool(run("git", "-C", str(root), "status", "--porcelain")),
        "architectures": ["arm64", "x86_64"],
        "executableSHA256": executable_hashes,
        "signatures": signatures,
        "appSandbox": True,
        "storeVariant": True,
        "realInputVerified": False,
        "appStoreUploaded": False,
        "appStoreApproved": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n")
    print("Validated universal launcher, both sandboxed helpers, signatures and resources.")


if __name__ == "__main__":
    main()
