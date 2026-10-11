# Mac native receiver window

The launcher is an AppKit application with a SwiftUI view. It embeds no web view and opens no browser. The bundle contains the launcher at `Contents/MacOS/SofaTap` and the .NET receiver at the fixed path `Contents/Helpers/SofaTapHost`.

The launcher starts that helper with `--native-ui`. Passing `--dry-run` explicitly to the launcher also passes this fixed flag to the helper; it is for transport/UI development and is clearly labelled in the window. The production app does not accept a helper executable override.

## Build

From the repository root, with Xcode selected:

```sh
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 -O \
  -o /tmp/SofaTap-arm64 desktop/macos/*.swift
xcrun swiftc -parse-as-library -swift-version 5 -target x86_64-apple-macosx15.0 -O \
  -o /tmp/SofaTap-x86_64 desktop/macos/*.swift
```

The release bundling script supplies the matching helper architecture, Info.plist, resources, signing and notarization. Both helper and launcher must be signed as part of the same distributed app. Compiling this launcher alone does not verify installation, Accessibility authorization, notarization, or iPhone input.

## Private pipe protocol

The helper's stdout is newline-delimited JSON. Each complete `state` has `name`, `platform: "macos"`, `inputStatus`, `dryRun`, `connected`, and `pairings: [{host, uri, qrPng}]`. `qrPng` is a base64 PNG. The protocol allowlists only `{"type":"refresh"}`, `{"type":"requestAccess"}` or `{"type":"quit"}`, each followed by a newline.

The Mac authorization button calls Apple's [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) with `kAXTrustedCheckOptionPrompt: true` **from the signed parent app**, only after an explicit click. Apple's prompt is asynchronous; its immediate return value never marks the helper as ready. A separate button opens normal Accessibility settings if the prompt does not appear. The UI gives manual `+` instructions for selecting the installed `Sofa Tap Receiver.app`. Install the signed app at a stable path before granting permission. The helper still independently checks AX trust and event-posting access in periodic states; granting parent permission is not itself proof that helper injection works. Neither startup, Refresh nor status reads prompt for permission, and dry-run cannot request it.

The UI model is main-actor isolated. Independent `DispatchSourceRead` readers consume stdout and drain stderr using nonblocking reads; the command writer operates away from the UI thread. Do not replace these with two `FileHandle.bytes` loops: Foundation's shared serial async IO actor can block stdout behind a quiet stderr. Frame sizes and PNG dimensions are bounded before decoding, and the UI stream buffers only the latest state. A missing update for eight seconds clears visible pairing state. Process exit, malformed frames and pipe failure show a generic error and clear the QR. Raw stderr is discarded. The QR and URI are held in memory, are never logged or saved by the launcher, and only reach the clipboard after an explicit Copy action. The helper separately owns the persistent pairing profile.

Closing the window or choosing Quit first sends `quit`. After 800 ms the launcher may call `terminate()` on its own child. It never looks up or kills other processes. If that child still has not exited after another four seconds, the app cancels its own exit and shows an error so it cannot silently leave an orphaned receiver.

This follows Apple's [Process](https://developer.apple.com/documentation/foundation/process), [terminationHandler](https://developer.apple.com/documentation/foundation/process/terminationhandler), [DispatchSourceRead](https://developer.apple.com/documentation/dispatch/dispatchsource/makereadsource(filedescriptor:queue:)) and [Pipe](https://developer.apple.com/documentation/foundation/pipe) APIs. Each dispatch source owns a duplicated file descriptor, closed only in its cancellation handler after in-flight handlers finish. Callbacks hop to the main actor before changing view state. The source also compiles in Swift 6 mode.

## Logic checks without launching a UI or helper

```sh
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 \
  -o /tmp/SofaTap-ProtocolTests desktop/macos/ReceiverProtocol.swift \
  desktop/macos/tests/ReceiverProtocolTests.swift
/tmp/SofaTap-ProtocolTests
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx15.0 \
  -o /tmp/SofaTap-PipeTests desktop/macos/ReceiverProtocol.swift \
  desktop/macos/ReceiverPipeReader.swift desktop/macos/tests/ReceiverPipeTests.swift
/tmp/SofaTap-PipeTests
```

The checks cover fragmented UTF-8 frames, periodic permission/connection changes, network selection and removal, bounded framing, malformed messages/images, and command serialization. Real anonymous-pipe checks additionally cover a permanently quiet stderr, stderr output larger than pipe capacity, stdout EOF and malformed JSON. They do not launch `NSApplication`, a receiver, a socket, or any input injection. Native window rendering, closing/quit behavior with a real helper, and phone-to-desktop input need separate live acceptance.
