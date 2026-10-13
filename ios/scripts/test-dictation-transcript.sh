#!/bin/bash
# Exercise the production recognition accumulator without requesting permissions,
# opening a microphone, launching an application window or sending OS input.
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
DICTATION_SDK="$(xcrun --sdk macosx --show-sdk-path)"
DICTATION_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sofatap-dictation-tests.XXXXXX")"
trap 'rm -rf "$DICTATION_STAGE"' EXIT
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-ios17.0-macabi" -sdk "$DICTATION_SDK" \
    -F "$DICTATION_SDK/System/iOSSupport/System/Library/Frameworks" \
    -I "$DICTATION_SDK/System/iOSSupport/usr/include" \
    "$REPO_ROOT/ios/SofaTap/Core/SpeechDictationController.swift" \
    "$REPO_ROOT/tests/DictationTranscriptTests.swift" \
    -o "$DICTATION_STAGE/dictation-transcript-tests"
"$DICTATION_STAGE/dictation-transcript-tests"
