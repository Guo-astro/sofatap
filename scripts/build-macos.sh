#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
if [ "$(uname -s)" != "Darwin" ]; then
  echo "Build on macOS with Xcode Command Line Tools installed." >&2
  exit 1
fi
architecture="${1:-arm64}"
case "$architecture" in
  arm64) machine_arch="arm64" ;;
  x64) machine_arch="x86_64" ;;
  *) echo "Usage: bash scripts/build-macos.sh [arm64|x64]" >&2; exit 1 ;;
esac
if [ "$#" -gt 1 ]; then
  echo "Build one architecture at a time: arm64 or x64." >&2
  exit 1
fi
runtime="osx-$architecture"
dotnet_cmd="${SOFATAP_DOTNET:-$repo_dir/.tools/dotnet/dotnet}"
if [ ! -x "$dotnet_cmd" ]; then
  dotnet_cmd="$(command -v dotnet || true)"
fi
if [ -z "$dotnet_cmd" ]; then
  echo "Install the .NET 10 SDK, or set SOFATAP_DOTNET to its executable." >&2
  exit 1
fi
for utility in python3 codesign ditto iconutil sips lipo; do
  if ! command -v "$utility" >/dev/null; then
    echo "Required build utility is missing: $utility" >&2
    exit 1
  fi
done

build_dir="$repo_dir/artifacts/macos-build/$runtime"
release_name="SofaTap-macOS-$architecture"
# File Provider/iCloud folders can attach FinderInfo to a newly created .app,
# invalidating codesign. Assemble and sign outside that folder; publish the ZIP.
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/sofatap-macos.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
release_dir="$stage_dir/$release_name"
app_dir="$release_dir/Sofa Tap Receiver.app"
publish_dir="$build_dir/self-contained"
mkdir -p "$build_dir"
# Recreate only this architecture's generated publish directory.
rm -rf "$publish_dir"
mkdir -p "$publish_dir" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

"$dotnet_cmd" publish host/SofaTap.Host.csproj -c Release -r "$runtime" \
  --artifacts-path "$build_dir/intermediate" --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:PublishTrimmed=false -p:DebugType=None -p:DebugSymbols=false -o "$publish_dir"
if [ ! -x "$publish_dir/SofaTap" ]; then
  echo "Publish did not produce the expected native SofaTap executable." >&2
  exit 1
fi
if [ "$(lipo -archs "$publish_dir/SofaTap")" != "$machine_arch" ]; then
  echo "Published executable does not match the requested architecture." >&2
  exit 1
fi
cp "$publish_dir/SofaTap" "$app_dir/Contents/MacOS/SofaTap"
python3 - "$publish_dir" "$app_dir/Contents/Resources" <<'PY'
import json
from pathlib import Path
import shutil
import sys

publish, resources = map(Path, sys.argv[1:])
for item in publish.iterdir():
    if item.name == "SofaTap":
        continue
    # This receiver serves its dashboard from code, with no static asset routes.
    # Non-code files cannot live in Contents/MacOS under strict bundle signing.
    if item.name != "SofaTap.staticwebassets.endpoints.json" or json.loads(item.read_text())["Endpoints"]:
        raise SystemExit("Review the macOS bundle location of new publish content: " + item.name)
    shutil.copyfile(item, resources / item.name)
PY

python3 - "$repo_dir" "$app_dir" "$runtime" <<'PY'
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

root, app = map(Path, sys.argv[1:3])
version = ET.parse(root / "host/SofaTap.Host.csproj").findtext(".//Version")
if not version or not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+].+)?", version):
    raise SystemExit("Expected a semantic version in the receiver project")
short_version = re.split(r"[-+]", version)[0]
build = subprocess.check_output(["git", "rev-list", "--count", "HEAD"], cwd=root, text=True).strip()
info = {
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleIdentifier": "com.chekusu.sofatap.receiver",
    "CFBundleExecutable": "SofaTap",
    "CFBundleName": "Sofa Tap Receiver",
    "CFBundleDisplayName": "Sofa Tap Receiver",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": short_version,
    "CFBundleVersion": build,
    "CFBundleIconFile": "SofaTap.icns",
    "LSApplicationCategoryType": "public.app-category.utilities",
    "LSMinimumSystemVersion": "15.0",
    "LSUIElement": True,
    "NSHighResolutionCapable": True,
    "NSLocalNetworkUsageDescription": "Sofa Tap 通过家庭局域网接收你已配对的 iPhone 发来的鼠标和文字操作。",
    "NSHumanReadableCopyright": "Copyright © CHEKUSU INC. Sofa Tap is available under the MIT license.",
}
with (app / "Contents/Info.plist").open("wb") as output:
    plistlib.dump(info, output)
(app / "Contents/PkgInfo").write_bytes(b"APPL????")
PY

# Format conversion only: use the repository's existing iPhone app artwork.
iconset="$build_dir/SofaTap.iconset"
mkdir -p "$iconset"
icon_source="$repo_dir/ios/SofaTap/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
for points in 16 32 128 256 512; do
  sips -z "$points" "$points" "$icon_source" --out "$iconset/icon_${points}x${points}.png" >/dev/null
  pixels=$((points * 2))
  sips -z "$pixels" "$pixels" "$icon_source" --out "$iconset/icon_${points}x${points}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/SofaTap.icns"

"$dotnet_cmd" msbuild host/SofaTap.Host.csproj -t:ResolveFrameworkReferences \
  -p:RuntimeIdentifier="$runtime" -p:SelfContained=true -p:PublishSingleFile=true \
  -p:UseArtifactsOutput=true -p:ArtifactsPath="$build_dir/intermediate" \
  -getItem:ResolvedSingleFileHostPack > "$build_dir/host-pack.json"
python3 scripts/package-licenses.py \
  --assets "$build_dir/intermediate/obj/SofaTap.Host/project.assets.json" \
  --host-pack "$build_dir/host-pack.json" \
  --runtime "$runtime" --destination "$app_dir/Contents/Resources/licenses"
cp LICENSE THIRD-PARTY-NOTICES.md "$app_dir/Contents/Resources/"
cp LICENSE THIRD-PARTY-NOTICES.md "$release_dir/"
cp docs/MAC-START.md "$release_dir/开始使用.md"
cp docs/MAC-START.md "$app_dir/Contents/Resources/开始使用.md"

# Ad-hoc signing makes this a coherent local test bundle. It is not a Developer
# ID signature, notarization, or an assertion that Gatekeeper trusts this build.
codesign --force --sign - --identifier com.chekusu.sofatap.receiver \
  --entitlements scripts/macos/Receiver.entitlements.plist "$app_dir"
codesign --verify --strict --verbose=2 "$app_dir"

python3 - "$repo_dir" "$release_dir" "$runtime" "$dotnet_cmd" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root, release = map(Path, sys.argv[1:3])
exe = release / "Sofa Tap Receiver.app/Contents/MacOS/SofaTap"
manifest = {
    "runtime": sys.argv[3],
    "bundleIdentifier": "com.chekusu.sofatap.receiver",
    "architectureCount": 1,
    "signature": "ad-hoc",
    "notarized": False,
    "minimumMacOS": "15.0",
    "sourceRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
    "sourceDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip()),
    "sdkVersion": subprocess.check_output([sys.argv[4], "--version"], cwd=root, text=True).strip(),
    "builtAt": datetime.now(timezone.utc).isoformat(),
    "executableSHA256": hashlib.sha256(exe.read_bytes()).hexdigest(),
    "iconSource": "ios/SofaTap/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "physicalInputVerified": False,
}
(release / "BUILD-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY
cp "$release_dir/BUILD-MANIFEST.json" "$build_dir/BUILD-MANIFEST.json"

archive="$repo_dir/artifacts/SofaTap-macOS-$architecture.zip"
rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$release_dir" "$archive"
cd "$repo_dir/artifacts"
shasum -a 256 "SofaTap-macOS-$architecture.zip" > "SofaTap-macOS-$architecture.zip.sha256"
echo "Built artifacts/SofaTap-macOS-$architecture.zip (ad-hoc signed; not notarized)"
