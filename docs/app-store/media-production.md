# Sofatap App Store media production

This workflow uses original physical iPhone screenshots and screen recordings. It does not control a phone, synthesize a connection, animate a still as if it were captured video, or upload to App Store Connect. The renderer uniformly scales the complete captured screen into a separate caption canvas. All status bars and app content are retained; there is no crop, recoloring, mock device UI, or replacement screen. The only allowed source-pixel exception is a documented privacy blur over private network address numerals in a real device-list screenshot; all pixels outside those declared rectangles must match the preserved original exactly.

## Deliverables and capture plan

Start with five screenshots each for `en-US`, `zh-Hans`, and `ja`: touchpad, keyboard, device management, QR scanner, and guide. See [the storyboard](media-storyboard.json) for the draft copy and exact asset IDs. A sixth dictation image needs its own genuine physical capture. Capture UI in the corresponding language; do not translate UI by compositing labels onto it. Additional languages use the same asset contract and explicit copy/source entries.

Capture the installed reviewed build, record its version/build and device OS, and preserve raw originals. Use an owned real receiver and ordinary product navigation for connected states; fixture data should be fictional and not personal. The connected indicator must come from an authenticated connection. Scanner captures must not contain a valid pairing QR, token, local endpoint, private desk contents, or another person's information. Prefer a neutral camera view. Keep an unmodified private original. A device-list screenshot may use the narrow privacy exception below; otherwise reject a sensitive source and recapture.

The 24-second preview uses actual screen-recorded clips: touchpad (6 s), keyboard (6 s), sending text (4 s), guide (4 s), scanner (4 s). The device list is omitted from video to avoid exposing private addresses. Capture several seconds of handles around each action. A continuous original can supply multiple slots with explicit `startSeconds`; use either a number or a locale-to-number mapping when recordings have different timings. Store the original recording hash before editing. Do not accelerate operations or invent finger gestures. An OS screen recording or QuickTime device capture is preferred; a genuine phone framebuffer stream can also be recorded if the capture method, actual timestamps, frame dimensions and frame cadence are retained. Captures from a simulator, website demo, generated illustration, or desktop preview do not satisfy this physical-device production requirement.

## Apple specifications checked 2026-10-14

- Screenshots: 1–10 per size, PNG/JPEG with no transparency. The renderer emits 1320 × 2868 and 1206 × 2622 portrait RGB PNGs, representing the listed large and medium Dynamic Island categories. Apple currently documents a medium-display requirement and category scaling; inspect the app's actual available ASC sets before upload. iPad needs its own qualifying assets if the submitted app supports iPadOS. [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
- Preview: 886 × 1920 portrait, 15–30 seconds, at most 30 fps, under 500 MB. Export H.264 progressive High Profile no higher than level 4.0, targeting 10–12 Mbps. The pipeline uses stereo AAC, 48 kHz, target 256 kbps, and selects a poster at five seconds. Source audio is muted to avoid private speech; the output carries a silent audio track. [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/).
- Store previews must use captured video of the app, with explanatory narration/overlays allowed. This preview excludes filmed hands, living-room footage, desktop screen inserts, invented animations of the app and claims for unreleased automation/TV support. Screenshots show the app in use; proposed captions describe only available functionality. [Review Guidelines 2.3.3–2.3.4](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata), [App Preview guidance](https://developer.apple.com/app-store/app-previews/).

These checks prepare a technically valid asset; Apple acceptance and the final displayed storefront layout remain separate outcomes.

## Private capture manifest

Keep the manifest and raw recordings under ignored `artifacts/` or a task cache, not in public source. Use the following schema, replacing every value with measured information. A hash placeholder is intentionally invalid. `publicReview: approved` is a producer's factual inspection record that the capture can be published, not a new permission prompt.

```json
{
  "version": 1,
  "brand": "Sofatap",
  "assets": {
    "touchpad.en-US": {
      "path": "raw/en-US/touchpad.png",
      "sha256": "REPLACE_WITH_ACTUAL_SHA256",
      "kind": "screenshot",
      "physicalDevice": true,
      "capturedAt": "REPLACE_WITH_CAPTURE_TIMESTAMP",
      "deviceModel": "REPLACE_WITH_OBSERVED_MODEL",
      "osVersion": "REPLACE_WITH_OBSERVED_OS",
      "appVersion": "1.0",
      "appBuild": "15",
      "uiLocale": "en-US",
      "captureMethod": "REPLACE_WITH_ACTUAL_CAPTURE_METHOD",
      "publicReview": "approved",
      "containsCredentials": false,
      "uiAlterations": "none"
    }
  }
}
```

Videos use the same fields with `kind: video` and a recording path. The renderer checks original hashes, dimensions, physical provenance, reviewed publication suitability, source type and UI language. For a deliberate same-UI/different-caption language edition, `--allow-ui-locale-fallback` records that discrepancy in every output receipt; it must not be described as a localized UI capture.

For a continuous recording that includes private or non-app footage outside the selected clips, set `publicReview: approved-selected-trims` and `approvedRanges: [[startSeconds, endSeconds], ...]`. Visually review these ranges, including transitions. The renderer rejects every trim extending outside them and records that the whole original is not publishable. Preserve the complete original privately for provenance; do not distribute it as an approved store asset.

For the private-address exception, keep the raw image unchanged and create a separate prepared PNG. Set `uiAlterations: privacy-redaction-only`, add `originalCapture: {path, sha256}`, and record `privacyRedactions: [{bounds: [x, y, width, height], method: gaussian-blur, radius: 8, reason: private-network-address}]`. Rectangle coordinates use original pixels. Blur only the numeric address, retaining the OS/device label and all other UI. The loader verifies both hashes and rejects any change outside the rectangles. Public receipts retain the original hash and rectangles but omit the raw path and private address. This exception does not permit invented IP addresses, replacement labels, changed connection state, or video retouching.

## Rendering and quality checks

Dependencies: Python 3.10+, Pillow, `ffmpeg` with libx264/AAC, and `ffprobe`. Choose a font with the needed glyph coverage using `--font` when the platform defaults are unavailable. The task's bundled Python has Pillow; no global Python changes are needed.

```sh
python3 scripts/store-media/produce.py \
  --manifest artifacts/store-media/captures.json \
  --storyboard docs/app-store/media-storyboard.json \
  --output artifacts/store-media/output \
  --mode screenshots --locales en-US zh-Hans ja

python3 scripts/store-media/produce.py \
  --manifest artifacts/store-media/captures.json \
  --storyboard docs/app-store/media-storyboard.json \
  --output artifacts/store-media/output \
  --mode preview --locales en-US zh-Hans ja
```

`--mode validate` requires all screenshot and video slots and produces no media. `screenshots` can run before videos exist. `all` produces both. Rendering is sequential, with two encoder threads and one filter thread; do not fan out multiple locale encoders on the shared Mac or server.

Each screenshot receipt includes source hash/provenance, exact placement and uniform scale, output resolution/color mode/hash, and any UI-language fallback. Video receipts include all original capture hashes, trims, 1× playback, duration, codec, poster frame and output hash. The script decodes the entire final movie and probes dimensions, frame rate, audio, duration and file size. The public output manifest excludes source paths, hardware UDIDs and credentials.

The render output directory is private: `.production-inputs/` preserves exact capture manifests, storyboards and script versions under their SHA256 names so later locale additions cannot erase recipe provenance. Do not publish this directory. Use `scripts/store-media/package_gallery.py --source <render-output> --destination <delivery-directory> --locales en-US zh-Hans ja` to copy only receipt-listed final media, verify their hashes and build the mobile gallery. It writes a public-safe manifest, contact sheets and notes; it excludes raw recordings, private recipe snapshots and intermediate segments. Create the delivery ZIP only after the requested locales are complete.

When reusing a delivery directory, the packager first verifies its existing manifest and every managed media/tool hash. It refuses any unmanifested file or symlink before writing, leaving that directory untouched; preserve it and choose a fresh directory. Earlier locales remain listed with their receipts when new locales are added. A changed plan that would leave old media files unlisted is also refused. The package includes the public production scripts/notes and a complete `SHA256SUMS` file.

After rendering, inspect every actual image and representative video frames at native and storefront thumbnail sizes. Confirm glyph coverage, copy fitting, source aspect ratio, visible controls, no secret QR or personal information, and absence of glitches. Compare output screens against original captures. Do not claim optical QR pairing or destination text acceptance from a marketing frame. Final assets can then enter the separately authorized App Store Connect upload/review workflow.
