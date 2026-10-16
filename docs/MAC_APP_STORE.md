# Sofatap Receiver — Mac App Store preparation

Updated October 16, 2026. **Unpublished submission draft.** The basic store build is implemented and has software/build checks; real input through the final signed sandboxed app has not been accepted. This document does not record an upload, Apple approval or store availability. It does not change the iPhone app, its TestFlight builds or its separate App Store submission.

## Distribution scope

| Item | Store preparation |
| --- | --- |
| App name | Sofatap Receiver — proposed listing name; confirm availability |
| Bundle ID | `com.chekusu.sofatap.receiver`, unchanged from the website receiver |
| Initial package | macOS 15+, version 1.0, build 1 in the build configuration; confirm against the eventual Mac App Store record |
| Architectures | Apple Silicon and Intel binaries; Intel execution is not yet verified |
| Category | Utilities in the package; confirm the App Store Connect selection |
| Intended controls | Manual pointer movement, clicks, dragging, scrolling, keys and reviewed text sending |
| Unavailable in this build | Focused-field detection, automatic keyboard opening from focus hints, importing existing field text, and precise live editing |
| Other boundaries | No screen streaming, unattended AI operation, lock-screen unlocking or power-on guarantee |

The phone remains the controller, and the Mac keeps displaying its own screen. Text from the phone's keyboard or supported dictation stays in the review-and-send composer until Send. Ordinary key commands are separate from editing that local draft. Neither draft clearing nor local selection means the corresponding text on the Mac was changed. Sending does not append an extra Return; embedded line breaks may have an Enter effect in the receiving application.

The website distribution retains its full feature set. The store build uses a separate App Sandbox data container even though its bundle ID is unchanged. It does not import the website receiver's pairing credentials. Switching distributions requires a new scan/pairing. Quit the previous receiver before opening the other distribution; do not run both and assume they share credentials or a listening port. Preserve the old pairing until the replacement connection is verified, then remove an obsolete entry deliberately on the phone.

## Reviewer setup draft

1. Install the signed store candidate on an awake, unlocked Mac running macOS 15 or later. Use a compatible Sofatap iPhone app on iOS 17 or later, on the same reachable home network. Confirm the exact companion build and its publicly usable installation route before copying these notes into App Store Connect.
2. Open Sofatap Receiver. Allow local-network access on Mac and iPhone if requested. No Sofatap account or test credentials are required.
3. In the receiver, click **请求辅助功能授权** (Request Accessibility Access). This explicit action requests macOS event-posting permission. Follow the system prompt to **System Settings → Privacy & Security → Accessibility** and allow the installed **Sofatap Receiver**. If the entry is absent, use **+** to select that installed app. Complete any system authentication yourself. Return to the receiver and refresh; the helper's status must report ready. Merely allowing the parent app is not proof that the helper can send input.
4. At first setup, **登录时自动启动** (Start at Login) is preselected, but nothing is registered until **确认设置** (Confirm Settings) is clicked. Leave it selected and confirm to enable, or clear it and confirm to decline. The normal checkbox can change this choice later. Pending macOS approval is shown separately. Startup occurs after this user logs in; it does not unlock the Mac.
5. On iPhone, open the device selector, choose **Scan QR Code**, and scan the Mac receiver. No device-type selection is required. Confirm the Mac name after authentication; rename it locally if desired. Never send a real pairing code or link as review metadata.
6. In a harmless blank document, verify pointer movement, clicks, scroll, drag, ordinary keys and a short text draft followed by Send. Open the phone keyboard manually: automatic field detection and live editing are intentionally unavailable in this build. Check the actual destination before sending or repeating an action.
7. Close the receiver window and confirm the connection continues; reopen it through the Dock. Quit Sofatap to stop control. Reopen and confirm that the saved phone pairing reconnects without scanning again.

The receiver UI is currently Simplified Chinese. The translations above explain its controls for reviewers; translated listing copy does not claim English or Japanese app UI. The production store permission path uses `CGPreflightPostEventAccess` / `CGRequestPostEventAccess`, not AX field-inspection APIs.

## Listing copy drafts

Publish only after the final signed candidate passes the acceptance gates below. Keep the store's basic-feature limits in every localization.

### English (en-US)

**Name:** Sofatap Receiver

**Subtitle:** Your iPhone, your Mac remote

**Keywords:** remote,touchpad,mouse,keyboard,sofa,receiver,local network

Control your Mac from the sofa with your iPhone. Sofatap Receiver connects to the Sofatap iPhone app so you can move the pointer, click, drag and scroll while watching your Mac's display or connected TV.

Type on your iPhone or use supported phone dictation, review the text, then tap Send. Pair by scanning the receiver's QR code, and reconnect to the saved Mac later. You can enable Start at Login after confirming the initial setup choice.

This basic Mac edition sends manual mouse and keyboard actions. It does not detect text fields, open the phone keyboard automatically or synchronize live text editing. It does not stream the screen or unlock your Mac.

Requires macOS 15 or later, the Sofatap iPhone app on iOS 17 or later, a reachable local network, an unlocked Mac and macOS input permission. No Sofatap account is required. Built-in dictation depends on the iPhone and recognition language.

### Simplified Chinese (zh-Hans)

**Name:** Sofatap Receiver

**Subtitle:** 用 iPhone 操作你的 Mac

**Keywords:** 遥控,触控板,鼠标,键盘,沙发,接收器,局域网

坐在沙发上，用 iPhone 操作 Mac。Sofatap Receiver 与 Sofatap 手机 App 配对后，你可以移动指针、点击、拖动和滚动，画面继续显示在 Mac 或连接的电视上。

使用手机键盘或支持的听写功能输入，确认文字后点发送。扫描接收器二维码即可配对，之后可以重新连接已保存的 Mac。首次设置确认后，可启用登录时自动启动。

本商店基础版提供手动鼠标和键盘操作，不支持自动识别输入框、自动弹出手机键盘或实时编辑同步，也不提供屏幕传输或解锁 Mac。

需要 macOS 15 或更新版本、运行 iOS 17 或更新版本的 Sofatap iPhone App、可互通的本地网络，以及已解锁并授予输入权限的 Mac。无需 Sofatap 账号。内置听写是否可用取决于 iPhone 和识别语言。

### Japanese (ja)

**Name:** Sofatap Receiver

**Subtitle:** iPhone で Mac を操作

**Keywords:** リモコン,タッチパッド,マウス,キーボード,ソファ,受信,ローカルネットワーク

ソファに座ったまま、iPhone で Mac を操作。Sofatap Receiver を Sofatap の iPhone アプリとペアリングすると、Mac や接続したテレビの画面を見ながら、ポインタの移動、クリック、ドラッグ、スクロールができます。

iPhone のキーボードや対応する音声入力で文章を作り、内容を確認して送信。受信アプリの QR コードを読み取って接続し、保存した Mac へ再接続できます。初回設定で確認すると、ログイン時の自動起動も有効にできます。

このストア基本版は、手動のマウス・キーボード操作に対応します。入力欄の自動検出、iPhone キーボードの自動表示、リアルタイム編集の同期、画面転送、Mac のロック解除には対応していません。

macOS 15 以降、iOS 17 以降の Sofatap iPhone アプリ、相互に接続できるローカルネットワーク、ロック解除済みの Mac、および macOS の入力操作権限が必要です。Sofatap アカウントは不要です。アプリ内の音声入力は iPhone と認識言語により利用できない場合があります。

## Existing public URLs and privacy preparation

These URLs already appear in the repository's iPhone metadata; reuse only after checking their current content for this Mac edition:

- Support: <https://github.com/chekusu/sofatap/blob/main/docs/app-store/support.md>
- Privacy policy: <https://github.com/chekusu/sofatap/blob/main/PRIVACY.md>
- Marketing/project: <https://github.com/chekusu/sofatap>

The current support page describes the full receiver and older release versions. Before Mac submission, add a clearly scoped store setup section and confirm the privacy policy distinguishes the basic build's lack of text inspection. This draft does not change either page.

The candidate privacy answer is **Data Not Collected**, based on direct encrypted local input, local pairing storage, no Sofatap cloud relay and no advertising/analytics SDK. It is a draft to verify against the final app and bundled dependencies, then save and publish for the actual Mac app record. The privacy manifest currently declares no tracking or collected data and declares app-owned UserDefaults access (`CA92.1`); audit other required-reason APIs in the complete packaged runtime before submission. Do not equate a prepared manifest with published App Privacy answers.

## Evidence and remaining submission gates

Observed software checks in this development round:

- Swift 6 builds passed for the arm64 website launcher and arm64/x86_64 store launcher. The inspected arm64 store launcher has no undefined AX symbols and uses the intended CG permission functions.
- Each channel passed 37 injected login-item checks; 13 temporary-directory checks cover container containment, inherited extraction-path replacement and symlink escape rejection. These tests perform no real OS registration or authorization.
- Both channels rendered 13 offscreen view fixtures and passed four QR rendering/readback checks per set. These are layout fixtures, not store screenshots or physical acceptance.

Before claiming the app is ready to submit:

- Verify the final store-signed sandboxed parent/helper launch, helper identity and entitlements, local network access, permission denial/grant/revocation, and actual iPhone-to-Mac input. **Real mouse, keyboard and text input for this store candidate remain unaccepted. Intel has build coverage only.** Shared-Mac acceptance must use verified Yomado window and input isolation, without changing physical display arrangement.
- Verify optical QR pairing, correct Mac identification, local rename, restart/reconnect, same-bundle-ID distribution switching, and no replay of uncertain input. Test consented startup, declined startup, actual logout/login and system-disabled startup separately.
- Capture real screenshots of the final Mac app on the isolated display. Do not use generated UI or offscreen fixtures as application screenshots. Check localized listing assets against the app's actual interface languages.
- Confirm the correct Mac App Store app record, signing/provisioning, available name, final version/build, package validation, encryption/export answers, pricing, availability, rights and age-rating questionnaire. Do not copy unverified answers from the iPhone app.
- Verify support/privacy content and URLs; publish the final privacy answers. Confirm the public companion iPhone download route and exact tested build. Add current reviewer steps and approved contact details privately in App Store Connect; do not put contacts, credentials or real pairing material in Git.
- Archive, export and upload only the accepted candidate; read back processing and submission status. Mac review, iPhone review and TestFlight remain separate workflows. A successful build or upload is not review approval.

See the [native launcher implementation and checks](../desktop/macos/README.md) and the [receiver acceptance boundaries](ACCEPTANCE.md).
