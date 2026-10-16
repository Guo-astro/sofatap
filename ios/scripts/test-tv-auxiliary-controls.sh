#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
TV_TOOLS_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sofatap-tv-tools-tests.XXXXXX")"
trap 'rm -rf "$TV_TOOLS_STAGE"' EXIT
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
  "$REPO_ROOT/ios/SofaTap/Core/TVAuxiliaryControls.swift" \
  "$REPO_ROOT/tests/TVAuxiliaryControlsTests.swift" -o "$TV_TOOLS_STAGE/tests"
"$TV_TOOLS_STAGE/tests"
TV_TOOLS_SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-ios17.0-macabi" -sdk "$TV_TOOLS_SDK" \
  -F "$TV_TOOLS_SDK/System/iOSSupport/System/Library/Frameworks" \
  -I "$TV_TOOLS_SDK/System/iOSSupport/usr/include" \
  "$REPO_ROOT/ios/SofaTap/Core/TVAuxiliaryControls.swift" \
  "$REPO_ROOT/ios/SofaTap/Views/TVAuxiliaryPager.swift" \
  "$REPO_ROOT/ios/SofaTap/Views/NativeControls.swift" \
  "$REPO_ROOT/ios/SofaTap/Views/TouchParticleRenderer.swift" \
  "$REPO_ROOT/ios/SofaTap/Core/TouchGestureState.swift" \
  "$REPO_ROOT/ios/SofaTap/Core/GestureConfiguration.swift" \
  "$REPO_ROOT/tests/TVAuxiliaryNativeTests.swift" -o "$TV_TOOLS_STAGE/native-tests"
"$TV_TOOLS_STAGE/native-tests"
