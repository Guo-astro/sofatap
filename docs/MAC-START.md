# Sofa Tap Mac 接收端

Mac 接收端让你用 iPhone 控制 Mac 的鼠标，并把手机输入框里的文字发送到 Mac 当前选中的输入框。电脑和手机通过家庭局域网连接。手机可以使用系统听写或 Typeless 等第三方键盘；Sofa Tap 不采集或转发麦克风音频。

当前接收端使用 AppKit / SwiftUI 原生窗口。每份发行包的签名、公证与实机验收状态以随包 manifest、NOTARIZATION-RECEIPT.json 和验收记录为准；开发构建通过不等于这些步骤已完成。

## 选择与打开

1. Mac 需要 macOS 15 或更新版本。在苹果菜单的“关于本机”查看芯片：Apple M 系列选择 `SofaTap-macOS-arm64.zip`；Intel 处理器选择 `SofaTap-macOS-x64.zip`。两份安装包分别对应一种处理器，不是 Universal 应用。包内包含运行时，不需要安装 .NET、Python 或 Node。
2. 解压 ZIP，将 **Sofa Tap Receiver.app** 拖到“应用程序”文件夹。先固定安装位置，再授予权限；不要直接在 ZIP 或每次变化的下载目录里运行。
3. 双击应用。若 macOS 因无法验证开发者而阻止打开，请先确认来源与下载校验结果，只对你信任的这份测试应用使用“系统设置 → 隐私与安全”中的“仍要打开”。具体入口以当前系统提示为准；如果提示应用损坏或包含恶意软件，停止操作并联系维护者，不要绕过提示。
4. 接收端会显示原生配对窗口。选择家庭网络地址，直接扫描窗口中的二维码。不打开浏览器，不需要终端窗口。

校验文件 `SofaTap-macOS-arm64.zip.sha256` 或 `SofaTap-macOS-x64.zip.sha256` 记录对应 ZIP 的 SHA256。默认源码构建使用 ad-hoc 本地签名；正式分发使用 CHEKUSU 的 Developer ID 签名与安全时间戳，并单独通过 Apple 公证后附带凭证。只在签名和公证回执均通过时称为已公证。不要关闭 Gatekeeper、系统完整性保护或整个防火墙。

## 允许控制 Mac

在原生配对窗口点“允许控制 Mac”或辅助功能授权入口，按系统提示打开“系统设置 → 隐私与安全 → 辅助功能”，开启 **Sofa Tap Receiver**。如果应用不在列表里，点添加按钮并选择“应用程序”中的 **Sofa Tap Receiver.app**。系统可能要求你使用密码或 Touch ID 确认。不同 macOS 版本的权限名称或位置可能略有不同，以系统提示为准。

授权对象应当是这个接收端应用。从 `.app` 正常启动后进行授权，不需要给 Terminal、dotnet 或浏览器授予控制电脑的权限。完成授权后返回原生窗口点“重新检查”；如果仍显示未获授权，先退出 Sofa Tap，再重新打开应用。

辅助功能权限能让应用移动鼠标、点击和输入文字，请只授予你信任的版本。包使用固定标识 `com.chekusu.sofatap.receiver`，但开发构建重新编译后签名身份可能变化；更换版本或移动安装位置后，macOS 可能要求重新授权。若旧条目失效，在辅助功能列表移除旧条目，再添加并授权当前 `.app`。不要使用重置全部隐私权限的命令。

## 手机配对与测试

1. 让 iPhone 与 Mac 处于同一个受信任的家庭局域网。Mac 可以用网线，iPhone 使用同一路由器的 Wi-Fi。访客网络的设备隔离可能阻止连接。
2. 如果 macOS 提示允许 Sofa Tap 使用本地网络或接收入站连接，根据你对这个家庭网络和应用的信任作出选择。接收端不提供网页配对端口；手机控制使用 TCP 53319，不需要路由器端口转发。
3. 打开 iPhone 上的 Sofa Tap，选择配对电脑并扫描 Mac 原生窗口中家庭网络地址对应的二维码。二维码包含控制凭据，不要公开截图或转发给其他人。
4. 在 Mac 打开“文本编辑”，新建文稿并点击正文。先用手机触控板移动、左键点击、右键点击和滚动，再发送 `你好 Mac 👋`。手机点“发送”才会发出文字，不会自动追加提交操作。
5. 验证系统听写后，再在手机文本框中切换 Typeless，检查返回 App 后草稿是否保留。中文、日文、emoji、组合字符和多行文字需要在实际使用的软件里分别测试。

手机提示已发送，只表示接收端已向系统提交输入事件，并不证明目标软件已经保存或提交。超时可能表示结果未知；先查看 Mac 上的内容，再决定是否重发。锁屏、登录界面、系统安全确认、某些密码框和拒绝模拟输入的程序不保证可用。

## 退出与更新

在 Mac 原生窗口点 **退出 Sofa Tap**，或关闭窗口。原生 App 会请求接收组件停止、断开手机，并尽力释放由它按住的鼠标按钮。父窗口进程异常结束时，管道关闭也会停止接收组件。

如果窗口没有响应，可打开“活动监视器”，搜索 **SofaTap**，确认是 Sofa Tap Receiver.app 对应进程，选择“停止 → 退出”。优先使用正常“退出”；强制退出不能保证执行程序的输入释放逻辑。

更新前先退出接收端，再替换“应用程序”中的旧版本，重新打开并检查权限。这个测试包不会添加登录启动项，也不会修改防火墙或已有辅助功能权限。配对凭据保存在当前用户的本地应用数据目录，不在 `.app` 内；替换 `.app` 不会主动清除配对数据。电脑网络地址、证书或凭据改变后需要重新扫码。

## 构建与分发状态

开发者在 macOS 上分别运行 `bash scripts/build-macos.sh arm64` 和 `bash scripts/build-macos.sh x64`。构建脚本仅生成 `.app`、ZIP 与校验文件，不安装、不启动接收服务、不授予权限。现有 iPhone 图标只做 `.icns` 格式转换，后续可以随正式视觉方案一起替换。

每份 ZIP 内有 `BUILD-MANIFEST.json`，记录体系结构、源代码版本、SDK、本地签名状态以及是否包含未提交修改。构建成功、签名完整性验证、传输演练和真正的手机输入验收是不同步骤；`physicalInputVerified: false` 表示打包流程没有作出实机验收声明。Intel 包即使在 Apple Silicon 上交叉构建成功，也仍需在真实 Intel Mac 上验收。

原生界面位于 `Contents/MacOS/SofaTap`，接收组件位于 `Contents/Helpers/SofaTapHost`，通过仅继承给子进程的内存管道通信。二维码和配对密钥不写入界面日志，也不通过 HTTP 页面提供。

应用包的 `Contents/Resources` 内含项目 MIT 许可证、第三方说明和实际解析到的依赖许可证。开发构建准备公开给普通用户之前，需要使用 CHEKUSU 的 Developer ID 完成正式签名、公证，并验证更新后的授权体验；具体命令见 [公证说明](NOTARIZATION.md)。

系统行为参考：[Apple 辅助功能权限说明](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)、[Apple 打开未知开发者应用说明](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)、[.NET 10 支持的系统](https://github.com/dotnet/core/blob/main/release-notes/10.0/supported-os.md)。
