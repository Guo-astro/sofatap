#!/bin/bash
# Gesture preferences and input arbitration with synthetic touches only.
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
GESTURE_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sofatap-gesture-tests.XXXXXX")"
trap 'rm -rf "$GESTURE_STAGE"' EXIT
xcrun swiftc -warnings-as-errors \
    "$REPO_ROOT/ios/SofaTap/Core/GestureConfiguration.swift" \
    "$REPO_ROOT/tests/GestureConfigurationTests.swift" \
    -o "$GESTURE_STAGE/preferences"
"$GESTURE_STAGE/preferences"
xcrun swiftc -warnings-as-errors \
    "$REPO_ROOT/ios/SofaTap/Core/GestureConfiguration.swift" \
    "$REPO_ROOT/ios/SofaTap/Core/TouchGestureState.swift" \
    "$REPO_ROOT/tests/CustomTouchGestureTests.swift" \
    -o "$GESTURE_STAGE/touch"
"$GESTURE_STAGE/touch"
xcrun swiftc -warnings-as-errors \
    "$REPO_ROOT/ios/SofaTap/Core/GestureConfiguration.swift" \
    "$REPO_ROOT/ios/SofaTap/Core/DeviceGuideContext.swift" \
    "$REPO_ROOT/tests/DeviceGuideContextTests.swift" \
    -o "$GESTURE_STAGE/guide"
"$GESTURE_STAGE/guide"
