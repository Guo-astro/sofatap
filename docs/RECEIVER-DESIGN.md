# Sofatap receiver design — Mint Calm

The creator selected **暮色薄荷 / Mint Calm** (`mint-calm`, concept 01) on 2026-10-12. It is the shared visual direction for the **native Windows, macOS and Linux receiver windows**. The [selected generated reference](../output/imagegen/sofatap-ui-concepts-2026-10-11/01-mint-calm.png) is a concept illustration, not a product screenshot or a usable pairing code. Its original generation prompts remain unchanged.

## People and purpose

People on a sofa should be able to pair an iPhone with their living-room computer without technical knowledge. The receiver has one primary job: show a readable pairing code and an honest connection/control state. Keep the screen calm, legible from a short distance, and easy to return to after setup.

## Shared palette and geometry

| Token | Value | Use |
| --- | --- | --- |
| Canvas | `#11191B` | Window content background |
| Surface | `#1E2A2C` | Pairing card and status pill |
| Border | `#334346` | Quiet card/control boundary |
| Mint | `#98E9C4` | Copy-link action, ready indicator, keyboard focus |
| Text | `#F0F5F3` | Main content |
| Muted | `#A8BAB7` | Instructions and footer |
| QR island | `#FFFFFF` | Black QR modules with an intact white quiet zone |

Aim for about 470 × 700 logical points of content, with 24–28 points of outer spacing, 16–20 point card corners, a 28–30 point headline, and 12–15 point supporting text. Keep a roughly 224-point square QR image plus padding. Use nearest-neighbor image scaling; never recolor, decorate, crop or place a logo over the real QR. Smaller windows, long device names and permission/error text must remain reachable through wrapping or scrolling.

Use native system typography and native window controls. Preserve platform keyboard navigation and visible focus. Do not redraw the operating system's window controls or substitute a new cursor/sofa glyph for the established brand artwork.

## Content order

1. A compact, centered status pill. Ready, connected, dry-run, permission needed, startup, failure and shutdown are distinct states. Color always has a text equivalent.
2. **扫码，坐回沙发** and **在 iPhone 上打开 Sofatap，扫描二维码**.
3. One pairing card: white QR island, actual computer name and network/address choice, then a full-width mint **复制配对链接** action.
4. Same-network advice and a short warning that the pairing code/link grants control and should not be shared.
5. Quiet **刷新** and **退出** actions. Closing the window still stops its owned backend.

The illustration's “客厅电脑” and “家庭网络” are placeholders. Production shows the actual computer and available address choices. Permission requests remain explicit platform actions; changing appearance must never grant permission, start input or mark an unavailable desktop ready. Failed or stopping receivers clear/disable stale QR and copy actions.

## Pairing links

Copying is an explicit user action. A bounded, validated `sofatap://pair` URI stays in memory and is copied only when the selected pairing is available. Never show it in a label, print it in diagnostics, or save it into design artifacts. Missing/invalid optional URIs disable Copy while preserving compatibility with QR-only snapshots. The clipboard is only touched by the user's Copy action; ordinary remote text input keeps its existing clipboard-free behavior.

## Scope and verification

The iPhone keeps its existing single touch surface, internal logo/scan/microphone/keyboard controls, moving dot field and touch ripples. The desktop choice does not add a touchpad, microphone or particle field to receiver windows.

Use synthetic offline fixtures and isolated rendering to review layout and states. Never publish live QR images, credentials or a private machine identity. On the shared Mac, do not activate receiver/test windows on physical displays; live input still requires proven Yomado isolation. Native render/build checks do not establish camera pairing, physical input, signed installation, notarization, Windows lock-screen control or PIN acceptance. Installed releases remain unchanged until a separately verified installation.
