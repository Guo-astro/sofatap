#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
TV_TOOLS_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sofatap-tv-tools-tests.XXXXXX")"
trap 'rm -rf "$TV_TOOLS_STAGE"' EXIT
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
  "$REPO_ROOT/ios/SofaTap/Core/TVAuxiliaryControls.swift" \
  "$REPO_ROOT/tests/TVAuxiliaryControlsTests.swift" -o "$TV_TOOLS_STAGE/tests"
"$TV_TOOLS_STAGE/tests"
