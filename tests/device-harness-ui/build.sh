#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
output="${1:?Usage: build.sh /absolute/output/SofatapDeviceHarness}"
case "$output" in /*) ;; *) printf '%s\n' 'Output must be an absolute path.' >&2; exit 64 ;; esac
mkdir -p "$(dirname "$output")"
xcrun swiftc -parse-as-library -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" -framework AppKit -framework CoreGraphics \
  "$root/HarnessView.swift" -o "$output"
printf '%s\n' "Built $output; not launched."
