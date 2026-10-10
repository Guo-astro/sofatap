#!/bin/bash
# Source-identical fallback when installed Xcode SDK/runtime versions prevent destination selection.
# This does not install to a device, create a provisioning profile, or prove physical-device behavior.
set -euo pipefail
IOS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_MODE="${1:-simulator}"
case "$BUILD_MODE" in
  simulator) BUILD_SDK=iphonesimulator; BUILD_TARGET=arm64-apple-ios17.0-simulator; BUILD_PLATFORM=iPhoneSimulator ;;
  device) BUILD_SDK=iphoneos; BUILD_TARGET=arm64-apple-ios17.0; BUILD_PLATFORM=iPhoneOS ;;
  *) printf 'Usage: %s [simulator|device]\n' "$0" >&2; exit 2 ;;
esac
BUILD_SDK_PATH="$(xcrun --sdk "$BUILD_SDK" --show-sdk-path)"
# FileProvider-backed Documents folders may add FinderInfo immediately after xattr removal.
# Build and sign in a fresh temporary directory, never mutate global Xcode caches or simulators.
BUILD_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sofatap-ios-${BUILD_MODE}.XXXXXX")"
APP_BUNDLE="$BUILD_STAGE/SofaTap.app"
mkdir -p "$APP_BUNDLE"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find "$IOS_ROOT/SofaTap" -type f -name '*.swift' | LC_ALL=C sort)
compile_args=(-emit-executable -target "$BUILD_TARGET" -sdk "$BUILD_SDK_PATH" -swift-version 5 -module-name SofaTap)
if [[ "$BUILD_MODE" == simulator ]]; then
  # Match Xcode's simulated entitlement sections. Putting iOS identity into the macOS
  # host code signature is restricted and makes amfid reject an adhoc simulator app.
  xcrun derq query -f xml -i "$IOS_ROOT/Simulator.entitlements" -o "$BUILD_STAGE/Simulator.entitlements.der" --raw
  compile_args+=(-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$IOS_ROOT/Simulator.entitlements"
                 -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __ents_der -Xlinker "$BUILD_STAGE/Simulator.entitlements.der")
fi
xcrun --sdk "$BUILD_SDK" swiftc "${compile_args[@]}" "${sources[@]}" -o "$APP_BUNDLE/SofaTap"
python3 - "$IOS_ROOT/SofaTap/Info.plist" "$APP_BUNDLE/Info.plist" "$BUILD_PLATFORM" "$BUILD_SDK" <<'PY'
import plistlib
import sys
from pathlib import Path
source, output, platform, sdk = sys.argv[1:]
data = plistlib.loads(Path(source).read_bytes())
data.update({
    'CFBundleName': 'SofaTap', 'CFBundleIdentifier': 'com.chekusu.sofatap',
    'CFBundleExecutable': 'SofaTap', 'CFBundleShortVersionString': '0.1.1',
    'CFBundleVersion': '2', 'CFBundleSupportedPlatforms': [platform],
    'DTPlatformName': sdk, 'MinimumOSVersion': '17.0', 'UIDeviceFamily': [1],
    'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconFiles': ['AppIcon60x60'], 'UIPrerenderedIcon': False}}
})
Path(output).write_bytes(plistlib.dumps(data))
PY
sips -z 120 120 "$IOS_ROOT/SofaTap/Assets.xcassets/AppIcon.appiconset/AppIcon.png" --out "$APP_BUNDLE/AppIcon60x60@2x.png" >/dev/null
sips -z 180 180 "$IOS_ROOT/SofaTap/Assets.xcassets/AppIcon.appiconset/AppIcon.png" --out "$APP_BUNDLE/AppIcon60x60@3x.png" >/dev/null
xattr -cr "$APP_BUNDLE"
if [[ "$BUILD_MODE" == simulator ]]; then
  codesign --force --sign - "$APP_BUNDLE"
  printf 'SIMULATOR_APP=%s\n' "$APP_BUNDLE"
else
  # Swift's linker may add an adhoc Mach-O signature; there is no distribution/development signing.
  printf 'UNPROVISIONED_DEVICE_APP=%s\n' "$APP_BUNDLE"
  printf 'Physical installation requires an Apple development team and provisioning in Xcode.\n'
fi
