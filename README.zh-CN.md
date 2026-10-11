# Sofatap

[English](README.md) · **简体中文** · [日本語](README.ja.md)

**把 iPhone 变成客厅电脑的遥控器。**

![Sofatap 使用场景：坐在沙发上，用 iPhone 操作连接客厅电视的电脑](docs/images/sofatap-living-room.png)

*AI 生成的产品场景示意图，并非应用截图。*

Sofatap 是 [chekusu](https://github.com/chekusu) 开发的开源遥控工具。把 iPhone 变成 Windows、Mac 或受支持 Linux 电脑的手势鼠标和语音／文字输入器。电脑画面留在电视上，人坐在沙发上就能操作。

[下载版本](https://github.com/chekusu/sofatap/releases) · [问题反馈](https://github.com/chekusu/sofatap/issues) · [MIT 许可](LICENSE)

## 可以做什么

- 一个大圆角触控区域，容纳 logo、扫码、麦克风和键盘入口。背景铺满缓慢流动的点阵，触摸会使附近点阵弯曲、偏移，点击产生涟漪。触控面不放说明文字；开启「减弱动态效果」后点阵保持静止，触摸反馈简化。
- 滑动移动鼠标、单击左键、连续双击右键、停留 300 ms 后拖动、双指滑动滚动。
- 点击底部麦克风使用设备支持的本机语音识别，也可使用 iPhone 键盘／Typeless。检查手机上的草稿后点**发送**，输入电脑当前聚焦的输入框；不会额外追加回车或提交操作，文字本身可包含换行。
- 扫描**电脑原生窗口**里的二维码配对：Mac 使用 AppKit/SwiftUI，Windows 使用 WinForms，Linux 使用 GTK3，无需打开浏览器。
- 通过家庭局域网连接，使用 WSS/TLS、证书指纹校验和本地配对凭据。保留草稿、发送确认和断线后不自动重放，帮助避免重复输入。

**当前是 alpha 预览版。** 单屏手势、麦克风和输入框焦点提示位于 `main` 的 0.6.0 开发源码（iPhone build 9）中；下方下载仍是先前 alpha 版本，不含这些更新。真实 iPhone 手势／听写、Typeless 和不同应用的焦点行为仍需验收。蓝牙连接和云中继尚未实现。参见[交互规格与后续独立 CUA 方向](docs/INTERACTION.md)。

点击 logo 查看连接详情和手势帮助。需要输入时，草稿区才出现在触控区域下方，保留文字检查与明确发送操作。[查看离线模拟器界面](docs/images/sofatap-single-screen.png)与[点阵动效预览](docs/images/sofatap-touch-effects.mp4)。这些仅展示本地渲染，不代表真实 iPhone 输入或性能已验证。

兼容接收端识别到提供辅助功能元数据的原生或网页可编辑输入框时，手机会自动弹出键盘。检测不读取框内内容；不支持检测、只读或安全输入框不会自动唤起输入界面。Linux 检测需要可选的 AT-SPI 桥接，仍可手动打开键盘。参见[焦点检测及平台限制](docs/TEXT-FOCUS.md)。

**实验性 Face ID 解锁：** 0.6.0 源码加入仅保存在本机 iPhone 钥匙串的密码保管，以及针对 Windows 本地账户或个人 Microsoft 账户密码的可选登录组件。需要明确启用并由管理员安装；普通扫码配对不会直接获得锁屏解锁能力。仅允许 Hello 登录或无密码账户可能无法使用此功能，Sofatap 不会修改这些设置。真实 Face ID 与 Windows 登录联合验收待完成。参见[设置、支持范围与验收要求](docs/FACE-ID-UNLOCK.md)。

## 平台进度

| 平台 | 当前状态 |
| --- | --- |
| iPhone | iOS 17+。iPhone 17 Pro Max 上的 0.3.0 (4) 已通过部分 iPhone 到 Mac 的联合验收；0.6.0 (9) 的单屏手势、麦克风和自动键盘仍需真机验收。 |
| Windows | 0.3.0 原生接收端已发布；本版桌面 UI 和手机联合实测待完成。 |
| Mac | macOS 15+。Apple Silicon 和 Intel 包均已公证；Apple Silicon 完成部分真机验收，Intel 输入待实测。 |
| Linux | 0.4.0 GTK3 原生接收端已发布；X11 输入通过隔离桌面检查。Wayland portal 为实验支持；真手机联调、真实 Wayland 合成器和 ARM64 运行待测。 |

[Mac 验收记录](docs/verification/macos-0.3.0.md)覆盖了 2026-10-11 的真实相机扫码、TLS 连接、文字精确读回和部分按键、指针操作。[Linux 验收记录](docs/verification/linux-0.4.0.md)覆盖原生 GTK 渲染、独立 Xvfb 桌面上的 X11 输入，以及私有 D-Bus 上的模拟 Wayland portal。这些记录不代表所有应用的兼容性均已验证。

Windows 通过 Win32 `SendInput` 输入；Mac 在用户明确授予辅助功能权限后使用 Quartz。Linux X11 需要 libX11、libXtst 和 libxdo；Wayland 需要兼容的 RemoteDesktop portal，并由用户在系统原生窗口中授权。Linux 每次文字操作最多接受 2,048 个 Unicode 标量值，不读写剪贴板。不受支持的 Wayland 会话保持不可用，不回退到 XWayland。详见 [Linux 要求与限制](desktop/linux/README.md)。

## 开始使用

### 安装电脑接收端

| 电脑 | 下载 | 安装说明 |
| --- | --- | --- |
| Windows x64 | [v0.3.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.3.0-alpha)：`SofaTap-Windows-x64.zip` 及对应 `.sha256` | 解压并运行 `SofaTap.exe`，防火墙只允许可信家庭专用网络访问。[Windows 启动说明](docs/WINDOWS-START.md) |
| Mac | [v0.3.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.3.0-alpha)：`SofaTap-macOS-arm64-notarized.zip` 或 `SofaTap-macOS-x64-notarized.zip` 及对应 `.sha256` | 根据电脑选择 Apple Silicon 或 Intel 包，两者均已公证。见 [Mac 安装与授权说明](docs/MAC-START.md)。 |
| Linux x64 / ARM64 | [v0.4.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.4.0-alpha)：`SofaTap-Linux-x64.tar.gz` 或 `SofaTap-Linux-arm64.tar.gz` 及对应 `.sha256` | 安装系统 GTK 和输入依赖后，解压并运行 `./sofatap`；原生窗口包含 Wayland 授权入口。[Linux 启动说明](desktop/linux/README.md) |

电脑端包已包含 .NET 运行时。Linux 仍需安装指南中列出的系统依赖。`--dry-run` 可演练连接流程，不产生桌面输入。

### 安装 iPhone App 并配对

1. 在 Xcode 中打开 `ios/SofaTap.xcodeproj`，选择自己的开发团队和已连接的 iPhone，然后运行 App。安装需要有效开发签名、设备配对和开发者模式。见 [iOS 构建说明](ios/README.md)。
2. 将 iPhone 与电脑接入可互通的家庭网络。访客 Wi-Fi 的设备隔离可能阻止连接。
3. 用 iPhone App 扫描接收端原生窗口里的二维码，或粘贴完整配对链接。
4. 在电脑上选中输入框，在手机上完成并检查文字，再明确点发送。发送结果不确定时，先确认电脑上的内容，再决定是否重发。

配对链接含有控制凭据，应只保留在自己的设备上。如果从最早使用 **Tiltro** 名称的版本升级，请阅读[升级说明](docs/WINDOWS-START.md#从旧名称版本升级)：这些版本的标识和存储位置不同，其配对和草稿不会自动迁移。本次 Sofatap 品牌拼写统一会保留现有 Sofatap 配对。

## 隐私与权限

Sofatap 通过局域网直接连接，项目没有云中继服务。配对使用固定证书校验；凭据保存在 iPhone Keychain、Windows DPAPI 或 Mac/Linux 上仅当前用户可读的接收端文件中。Mac 输入需要辅助功能权限，Wayland 输入需要用户明确授予 portal 权限。

麦克风仅在明确点击并取得所需权限后启动。受支持的本机识别将音频保留在手机上；Sofatap 不上传音频，也不静默切换到云端识别。识别文字保留在本地草稿中，直到用户点**发送**。系统听写和第三方输入法有各自的数据处理方式。

二维码通过本机私有管道传给原生电脑 UI，不使用网页配对。不要公开配对码、凭据或签名材料。仓库不包含开发账号、签名证书或 provisioning profile。通信与输入行为见 [PROTOCOL.md](PROTOCOL.md)，待完成的设备检查见[实机验收清单](docs/ACCEPTANCE.md)。

## 从源码构建

接收端需要 **.NET 10 SDK** 和 Python 3。如果 SDK 在自定义位置，将 `SOFATAP_DOTNET` 设为 `dotnet` 可执行文件路径。

```sh
# 在 Mac/Unix 上构建 Windows 分发包
bash scripts/build-windows.sh

# 在 macOS 上构建 Mac 分发包
bash scripts/build-macos.sh arm64
bash scripts/build-macos.sh x64

# 构建 Linux 分发包，支持交叉构建
bash scripts/build-linux.sh x64
bash scripts/build-linux.sh arm64
```

产物写入 `artifacts/`，附带许可和 SHA256 文件。Windows 和 Mac 包分别命名为 `SofaTap-Windows-x64.zip`、`SofaTap-macOS-<architecture>.zip`；Linux 为 `SofaTap-Linux-<architecture>.tar.gz`。Mac 默认使用 ad-hoc 开发签名；分发签名和 Apple 公证流程见 [NOTARIZATION.md](docs/NOTARIZATION.md)。

Windows 开发者可在 PowerShell 中构建底层接收组件；上面的完整分发包还包含原生窗口：

```powershell
dotnet publish host/SofaTap.Host.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```

分发构建产物时需附上 `LICENSE`、`THIRD-PARTY-NOTICES.md` 和对应依赖许可。打包脚本会收集实际解析到的运行时及 NuGet 版本的许可。

iPhone 使用仓库中的 Xcode 工程。修改 `ios/project.yml` 后，运行 `xcodegen generate --spec ios/project.yml` 重新生成工程。[iOS 说明](ios/README.md)也介绍了直接编译方式；设备编译成功不等于签名和安装已完成。

## 开发验证

在装有 .NET 10、Python 3 和 Xcode 的 Mac 上运行：

```sh
python3 -m pip install websockets==16.0
dotnet run --project tests/host/SofaTap.Host.Tests.csproj -c Release
dotnet run --project desktop/windows-login/Tests/Sofatap.Login.Tests.csproj -c Release
SOFATAP_DOTNET="$(command -v dotnet)" python3 tests/smoke.py
swiftc ios/SofaTap/Core/Pairing.swift tests/PairingTests.swift -o /tmp/sofatap-pairing-tests
/tmp/sofatap-pairing-tests
swiftc ios/SofaTap/Core/ReceiverState.swift tests/ReceiverStateTests.swift -o /tmp/sofatap-receiver-tests
/tmp/sofatap-receiver-tests
swiftc ios/SofaTap/Core/TouchGestureState.swift tests/TouchGestureTests.swift -o /tmp/sofatap-gesture-tests
/tmp/sofatap-gesture-tests
python3 tests/text_focus_linux.py
bash ios/scripts/build-manual.sh device
```

Host runner 使用模拟输入器。TLS/WebSocket 检查以 `--dry-run` 启动临时接收端，不向系统注入输入。最后一项编译未配置签名的 ARM64 iOS App，不安装到手机。CI 还执行各平台构建和隔离 Linux 桌面检查；相关命令见 [Linux 说明](desktop/linux/README.md#lifecycle-and-checks)。

构建、协议、虚拟桌面和物理设备检查分别证明不同层面的行为。0.6.0 后续验收仍包括实体单／双击、300 ms 长按拖动、滚动、粒子反馈与减弱动态效果、麦克风权限与识别、Typeless、不同应用的输入框焦点，以及各受支持桌面平台的手机联合测试。

## 源码目录

| 路径 | 内容 |
| --- | --- |
| `ios/` | 原生 iPhone App、Xcode 工程和工程生成配置 |
| `host/` | 共用接收协议、Windows/Mac 输入后端和 Linux worker 桥接 |
| `desktop/` | 原生配对窗口和 Linux 输入 worker |
| `tests/` | 协议、认证和输入边界检查 |
| `PROTOCOL.md` | 通信协议 |
| `docs/` | 安装指南和验收记录 |
| `scripts/build-*.sh` | 电脑端分发包构建 |
| `licenses/` | 第三方许可与通知原文 |

本机构建产物、配对凭据和签名材料不属于源码。命名背景见 [NAME.md](docs/NAME.md)。

## 参与和许可

欢迎提交 Issue 和 Pull Request，参与前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

Sofatap 采用 [MIT 许可](LICENSE)。第三方依赖通知见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
