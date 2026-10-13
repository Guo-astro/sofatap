#!/bin/bash
# Pure gesture checks and native view type checking; no window, device or OS input.
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
EDGE_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sofatap-edge-tests.XXXXXX")"
trap 'rm -rf "$EDGE_STAGE"' EXIT
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
    "$REPO_ROOT/ios/SofaTap/Core/EdgeScrollGesture.swift" \
    "$REPO_ROOT/tests/EdgeScrollGestureTests.swift" \
    -o "$EDGE_STAGE/edge-tests"
"$EDGE_STAGE/edge-tests"
EDGE_SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx swiftc -typecheck -swift-version 5 \
    -target "$(uname -m)-apple-ios17.0-macabi" -sdk "$EDGE_SDK" \
    -F "$EDGE_SDK/System/iOSSupport/System/Library/Frameworks" \
    -I "$EDGE_SDK/System/iOSSupport/usr/include" \
    "$REPO_ROOT/ios/SofaTap/Core/EdgeScrollGesture.swift" \
    "$REPO_ROOT/ios/SofaTap/Views/EdgeScrollStrip.swift"
