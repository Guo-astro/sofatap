#!/bin/bash
set -euo pipefail

: "${SRCROOT:?Run as the SofatapReceiver Xcode build phase}"
: "${TARGET_BUILD_DIR:?}"
: "${CONTENTS_FOLDER_PATH:?}"
: "${SOFATAP_STORE_INPUTS:?Run scripts/build-macos-store.sh first}"
contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
mkdir -p "$contents/Helpers/arm64" "$contents/Helpers/x64" "$contents/Resources"
for architecture in arm64 x64; do
  source="$SOFATAP_STORE_INPUTS/Helpers/$architecture/SofaTapHost"
  test -x "$source" || { echo "Missing prepared $architecture helper; run scripts/build-macos-store.sh." >&2; exit 1; }
  cp "$source" "$contents/Helpers/$architecture/SofaTapHost"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
    identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    test -n "$identity" || identity=-
    codesign --force --sign "$identity" --options runtime \
      --identifier "com.chekusu.sofatap.receiver.host.$architecture" \
      --entitlements "$SRCROOT/../../scripts/macos-store/Helper.entitlements.plist" \
      "$contents/Helpers/$architecture/SofaTapHost"
  fi
done
ditto "$SOFATAP_STORE_INPUTS/Resources" "$contents/Resources"
