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
release_dir="$repo_dir/artifacts/SofaTap-Windows-x64"
mkdir -p "$release_dir"
"$dotnet_cmd" publish host/SofaTap.Host.csproj -c Release -r win-x64 \
  --self-contained true -p:PublishSingleFile=true \
  -p:IncludeNativeLibrariesForSelfExtract=true -p:PublishTrimmed=false \
  -p:DebugType=None -p:DebugSymbols=false -o "$release_dir"
if [ ! -f "$release_dir/SofaTap.exe" ]; then
  echo "Publish did not produce the expected SofaTap.exe." >&2
  exit 1
fi
cp LICENSE "$release_dir/LICENSE"
cp THIRD-PARTY-NOTICES.md "$release_dir/THIRD-PARTY-NOTICES.md"
# A self-contained executable embeds runtime code. Preserve notices from the
# actual restored packages, including when the installed SDK selects a newer patch.
python3 - "$repo_dir" "$release_dir" <<'PY'
import json
from pathlib import Path
import re
import shutil
import sys

root, release = map(Path, sys.argv[1:])
assets = json.loads((root / "host/obj/project.assets.json").read_text())
package_folders = [Path(folder) for folder in assets["packageFolders"]]
packages = {}
for identity, metadata in assets["libraries"].items():
    if metadata.get("type") != "package":
        continue
    name, version = identity.rsplit("/", 1)
    if name.lower() == "microsoft.net.illink.tasks":
        continue  # Build-time tool, not distributed receiver code.
    packages[name.lower()] = version
for framework in assets["project"]["frameworks"].values():
    for dependency in framework.get("downloadDependencies", []):
        name, version_range = dependency["name"].lower(), dependency["version"]
        if not name.endswith(".win-x64"):
            continue
        match = re.fullmatch(r"\[([^,\]]+),\s*([^\]]+)\]", version_range)
        if not match or match[1] != match[2]:
            raise SystemExit("Expected an exact runtime version for " + name)
        packages[name] = match[1]
required_runtimes = {"microsoft.netcore.app.runtime.win-x64", "microsoft.aspnetcore.app.runtime.win-x64", "microsoft.netcore.app.host.win-x64"}
if not required_runtimes.issubset(packages):
    raise SystemExit("Resolved Windows runtime packages are missing from the restore manifest.")
licenses = release / "licenses"
if licenses.exists():
    shutil.rmtree(licenses)
licenses.mkdir()
resolved = []
for name, version in sorted(packages.items()):
    package = next((folder / name / version for folder in package_folders if (folder / name / version).is_dir()), None)
    if package is None:
        raise SystemExit("Resolved package is missing from the cache: " + name)
    destination = licenses / ("qrcoder" if name == "qrcoder" else name)
    destination.mkdir()
    documents = [file for file in package.iterdir() if file.is_file() and file.name.lower() in {"license", "license.txt", "license.md", "third-party-notices.txt", "thirdpartynotices.txt", "notice", "notice.txt"}]
    if name == "qrcoder" and version == "1.7.0":
        # This package declares MIT but omits the license file. Preserve the
        # original text retrieved from its exact upstream source commit.
        documents.append(root / "licenses/qrcoder/LICENSE.txt")
    if not any(file.name.lower().startswith("license") for file in documents):
        raise SystemExit("No license text found for shipped package: " + name + " " + version)
    for document in documents:
        shutil.copyfile(document, destination / document.name)
    resolved.append(name + " " + version)
(licenses / "RESOLVED-PACKAGES.txt").write_text("Resolved package licenses included in this release:\n" + "\n".join(resolved) + "\n", encoding="utf-8")
print("Included license documents for " + str(len(resolved)) + " resolved packages.")
PY
cp docs/WINDOWS-START.md "$release_dir/开始使用.md"
cp scripts/windows/Start-SofaTap.cmd "$release_dir/Start-SofaTap.cmd"
cp scripts/windows/Enable-Autostart.ps1 "$release_dir/Enable-Autostart.ps1"
cp scripts/windows/Disable-Autostart.ps1 "$release_dir/Disable-Autostart.ps1"
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
