#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
dotnet_cmd="${SOFATAP_DOTNET:-$repo_dir/.tools/dotnet/dotnet}"
if [ ! -x "$dotnet_cmd" ]; then
  dotnet_cmd="$(command -v dotnet || true)"
fi
if [ -z "$dotnet_cmd" ]; then
  echo "Install the .NET 10 SDK, or set SOFATAP_DOTNET to its executable." >&2
  exit 1
fi
build_dir="$repo_dir/artifacts/windows-native-build"
release_dir="$repo_dir/artifacts/SofaTap-Windows-x64"
backend_dir="$build_dir/backend"
frontend_dir="$build_dir/frontend"
# These directories contain generated release files only.
rm -rf "$release_dir" "$backend_dir" "$frontend_dir"
mkdir -p "$release_dir" "$backend_dir" "$frontend_dir"
version="$(tr -d '\r\n' < updates/desktop-version.txt)"
"$dotnet_cmd" publish host/SofaTap.Host.csproj -c Release -r win-x64 \
  --artifacts-path "$build_dir/backend-intermediate" --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:PublishTrimmed=false -p:DebugType=None -p:DebugSymbols=false -o "$backend_dir"
"$dotnet_cmd" publish desktop/windows/SofaTap.Desktop.csproj -c Release -r win-x64 \
  --artifacts-path "$build_dir/frontend-intermediate" --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:PublishTrimmed=false -p:DebugType=None -p:DebugSymbols=false -p:Version="$version" -o "$frontend_dir"
if [ ! -f "$backend_dir/SofaTap.exe" ] || [ ! -f "$frontend_dir/SofaTap.exe" ]; then
  echo "Publish did not produce both receiver and native-window executables." >&2
  exit 1
fi
cp -R "$backend_dir/." "$release_dir/"
mv "$release_dir/SofaTap.exe" "$release_dir/SofaTapHost.exe"
cp -R "$frontend_dir/." "$release_dir/"
cp LICENSE "$release_dir/LICENSE"
cp THIRD-PARTY-NOTICES.md "$release_dir/THIRD-PARTY-NOTICES.md"
# A self-contained executable embeds runtime code. Preserve notices from the
# actual restored packages, including when the installed SDK selects a newer patch.
# Native Windows SDKs can provide the host from packs/, without a NuGet restore entry.
"$dotnet_cmd" msbuild host/SofaTap.Host.csproj -t:ResolveFrameworkReferences \
  -p:RuntimeIdentifier=win-x64 -p:SelfContained=true -p:PublishSingleFile=true \
  -p:UseArtifactsOutput=true -p:ArtifactsPath="$build_dir/backend-intermediate" \
  -getItem:ResolvedSingleFileHostPack > "$build_dir/backend-host-pack.json"
"$dotnet_cmd" msbuild desktop/windows/SofaTap.Desktop.csproj -t:ResolveFrameworkReferences \
  -p:RuntimeIdentifier=win-x64 -p:SelfContained=true -p:PublishSingleFile=true \
  -p:UseArtifactsOutput=true -p:ArtifactsPath="$build_dir/frontend-intermediate" \
  -getItem:ResolvedSingleFileHostPack > "$build_dir/frontend-host-pack.json"
python3 - "$repo_dir" "$release_dir" "$build_dir" <<'PY'
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

root, release, build = map(Path, sys.argv[1:])
asset_paths = [build / "backend-intermediate/obj/SofaTap.Host/project.assets.json",
               build / "frontend-intermediate/obj/SofaTap.Desktop/project.assets.json"]
package_folders = set()
packages = {}
host_name = "microsoft.netcore.app.host.win-x64"
host_locations = []
document_names = {"license", "license.txt", "license.md", "third-party-notices.txt", "thirdpartynotices.txt", "notice", "notice.txt"}
def include(name, version):
    name = name.lower()
    if name in packages and packages[name] != version:
        raise SystemExit("Receiver and UI resolve different versions of " + name)
    packages[name] = version
for asset_path in asset_paths:
    assets = json.loads(asset_path.read_text())
    package_folders.update(Path(folder) for folder in assets["packageFolders"])
    for identity, metadata in assets["libraries"].items():
        if metadata.get("type") != "package":
            continue
        name, version = identity.rsplit("/", 1)
        if name.lower() == "microsoft.net.illink.tasks":
            continue  # Build-time tool, not distributed receiver code.
        include(name, version)
    for framework in assets["project"]["frameworks"].values():
        for dependency in framework.get("downloadDependencies", []):
            name, version_range = dependency["name"].lower(), dependency["version"]
            if not name.endswith(".win-x64"):
                continue
            match = re.fullmatch(r"\[([^,\]]+),\s*([^\]]+)\]", version_range)
            if not match or match[1] != match[2]:
                raise SystemExit("Expected an exact runtime version for " + name)
            include(name, match[1])
for component in ("backend", "frontend"):
    hosts = json.loads((build / (component + "-host-pack.json")).read_text(encoding="utf-8-sig"))["Items"]["ResolvedSingleFileHostPack"]
    if len(hosts) != 1 or hosts[0].get("RuntimeIdentifier") != "win-x64":
        raise SystemExit("Expected exactly one resolved Windows single-file host for " + component)
    host = hosts[0]
    version = host.get("NuGetPackageVersion", "")
    package = Path(host["PackageDirectory"])
    if (host.get("NuGetPackageId", "").lower() != host_name
            or not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?", version)
            or package.name != version or package.parent.name.lower() != host_name
            or host.get("PathInPackage", "").replace("\\", "/") != "runtimes/win-x64/native/singlefilehost.exe"
            or Path(host["Path"]).resolve() != (package / "runtimes/win-x64/native/singlefilehost.exe").resolve()):
        raise SystemExit("Resolved host package has an unexpected identity for " + component)
    include(host_name, version)
    host_locations.append(package)
required_runtimes = {"microsoft.netcore.app.runtime.win-x64", "microsoft.aspnetcore.app.runtime.win-x64",
                     "microsoft.netcore.app.host.win-x64", "microsoft.windowsdesktop.app.runtime.win-x64"}
if not required_runtimes.issubset(packages):
    raise SystemExit("Resolved receiver/UI runtime packages are missing from the restore manifests.")
licenses = release / "licenses"
if licenses.exists():
    shutil.rmtree(licenses)
licenses.mkdir()
resolved = []
for name, version in sorted(packages.items()):
    package = next((folder / name / version for folder in package_folders if (folder / name / version).is_dir()), None)
    if package is None and name != host_name:
        raise SystemExit("Resolved package is missing from the cache: " + name)
    destination = licenses / ("qrcoder" if name == "qrcoder" else name)
    destination.mkdir()
    documents = [file for file in package.iterdir() if file.is_file() and file.name.lower() in document_names] if package else []
    host_documents = {}
    if name == host_name:
        # A package-cache copy is a restored NuGet artifact. If only the SDK pack
        # exists, fetch the exact official package; never substitute another version
        # or skip notices. Compare the SDK's actual native hosts before using them.
        url = f"https://api.nuget.org/v3-flatcontainer/{name}/{version}/{name}.{version}.nupkg"
        archive = None
        if package is None:
            with urllib.request.urlopen(url, timeout=45) as response:
                payload = response.read(64 * 1024 * 1024 + 1)
            if len(payload) > 64 * 1024 * 1024:
                raise SystemExit("Resolved host package exceeds the download limit")
            archive = zipfile.ZipFile(io.BytesIO(payload))
            specs = [item for item in archive.namelist() if item.lower() == name + ".nuspec"]
            if len(specs) != 1:
                raise SystemExit("Downloaded host package is missing its exact NuGet manifest")
            metadata = ET.fromstring(archive.read(specs[0]))
            if (metadata.findtext("{*}metadata/{*}id") or "").lower() != name or metadata.findtext("{*}metadata/{*}version") != version:
                raise SystemExit("Downloaded host package identity does not match MSBuild")
            host_documents = {item: archive.read(item) for item in archive.namelist()
                              if "/" not in item and item.lower() in document_names}
        hashes = {}
        for binary in ("apphost.exe", "singlefilehost.exe"):
            relative = "runtimes/win-x64/native/" + binary
            expected = (package / relative).read_bytes() if package else archive.read(relative)
            digest = hashlib.sha256(expected).hexdigest()
            for location in host_locations:
                if hashlib.sha256((location / relative).read_bytes()).hexdigest() != digest:
                    raise SystemExit("Resolved SDK host differs from its matching NuGet package: " + binary)
            hashes[binary] = digest
        if archive:
            archive.close()
        (destination / "PROVENANCE.json").write_text(json.dumps({
            "package": name, "version": version, "officialPackage": url,
            "licenseSource": "NuGet cache" if package else "official NuGet download",
            "verifiedNativeHostSHA256": hashes,
        }, indent=2) + "\n", encoding="utf-8")
    if name == "qrcoder" and version == "1.7.0":
        # This package declares MIT but omits the license file. Preserve the
        # original text retrieved from its exact upstream source commit.
        documents.append(root / "licenses/qrcoder/LICENSE.txt")
    if not any(file.name.lower().startswith("license") for file in documents) and not any(name.lower().startswith("license") for name in host_documents):
        raise SystemExit("No license text found for shipped package: " + name + " " + version)
    for document in documents:
        shutil.copyfile(document, destination / document.name)
    for document, content in host_documents.items():
        (destination / document).write_bytes(content)
    resolved.append(name + " " + version)
(licenses / "RESOLVED-PACKAGES.txt").write_text("Resolved package licenses included in this release:\n" + "\n".join(resolved) + "\n", encoding="utf-8")
print("Included license documents for " + str(len(resolved)) + " resolved packages.")
PY
cp docs/WINDOWS-START.md "$release_dir/开始使用.md"
cp scripts/windows/Start-SofaTap.cmd "$release_dir/Start-SofaTap.cmd"
cp scripts/windows/Enable-Autostart.ps1 "$release_dir/Enable-Autostart.ps1"
cp scripts/windows/Disable-Autostart.ps1 "$release_dir/Disable-Autostart.ps1"
# The verified in-app updater requires a complete, version-bound file manifest.
# Pairing/TLS/startup preferences live in LocalAppData and never enter this archive.
python3 - "$release_dir" "$version" <<'PYMANIFEST'
from pathlib import Path
import hashlib, json, sys
release, version = Path(sys.argv[1]), sys.argv[2]
files = {path.relative_to(release).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
         for path in sorted(release.rglob("*")) if path.is_file()}
(release / "sofatap-package.json").write_text(json.dumps({
    "Product": "com.chekusu.sofatap.receiver.windows", "Version": version,
    "Architecture": "x64", "Files": files,
}, indent=2) + "\n", encoding="utf-8")
PYMANIFEST
cd "$repo_dir/artifacts"
# zipfile marks non-ASCII paths as UTF-8 so the Chinese guide keeps its name
# in Windows Explorer and standard ZIP readers.
python3 - "$release_dir" "$repo_dir/artifacts/SofaTap-Windows-x64.zip" <<'PYZIP'
from pathlib import Path
import sys
import zipfile

release, archive = map(Path, sys.argv[1:])
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
    for path in sorted(release.rglob("*")):
        if path.is_file():
            package.write(path, path.relative_to(release.parent).as_posix())
PYZIP
shasum -a 256 SofaTap-Windows-x64.zip > SofaTap-Windows-x64.zip.sha256
echo "Built artifacts/SofaTap-Windows-x64.zip"
