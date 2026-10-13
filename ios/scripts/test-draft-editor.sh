#!/bin/bash
# Exercise the production UIKit editor offscreen via Mac Catalyst. No simulator,
# application window, keyboard focus, pairing or OS input is used.
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
DRAFT_SDK="$(xcrun --sdk macosx --show-sdk-path)"
DRAFT_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sofatap-draft-tests.XXXXXX")"
trap 'rm -rf "$DRAFT_STAGE"' EXIT
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-ios17.0-macabi" -sdk "$DRAFT_SDK" \
    -F "$DRAFT_SDK/System/iOSSupport/System/Library/Frameworks" \
    -I "$DRAFT_SDK/System/iOSSupport/usr/include" \
    "$REPO_ROOT/ios/SofaTap/Views/NativeControls.swift" \
    "$REPO_ROOT/ios/SofaTap/Views/TouchParticleRenderer.swift" \
    "$REPO_ROOT/ios/SofaTap/Core/TouchGestureState.swift" \
    "$REPO_ROOT/tests/NativeDraftEditorTests.swift" \
    -o "$DRAFT_STAGE/draft-editor-tests"
"$DRAFT_STAGE/draft-editor-tests"
