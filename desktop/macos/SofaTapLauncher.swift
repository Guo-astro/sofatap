import AppKit
import SwiftUI

@main
enum SofaTapLauncher {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = LauncherDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class LauncherDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let receiver = ReceiverController()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Sofatap", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Sofatap", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Sofatap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Sofatap"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.039, green: 0.051, blue: 0.067, alpha: 1)
        window.minSize = NSSize(width: 440, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ReceiverView(receiver: receiver))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        receiver.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window?.makeKeyAndOrderFront(nil) }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        receiver.stop { [weak self] stopped in
            // Reply on the next main-loop turn, after AppKit receives terminateLater.
            DispatchQueue.main.async {
                sender.reply(toApplicationShouldTerminate: stopped)
                if !stopped { self?.window?.makeKeyAndOrderFront(nil) }
            }
        }
        return .terminateLater
    }
}

private enum Palette {
    static let background = Color(red: 0.039, green: 0.051, blue: 0.067)
    static let panel = Color(red: 0.078, green: 0.098, blue: 0.122)
    static let mint = Color(red: 0.722, green: 0.953, blue: 0.816)
    static let muted = Color(red: 0.65, green: 0.70, blue: 0.72)
}

struct ReceiverView: View {
    @ObservedObject var receiver: ReceiverController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if receiver.isStopping {
                    statusCard(icon: "hourglass", title: "正在退出", message: "正在断开手机并停止接收组件。", color: Palette.mint)
                } else if let failure = receiver.failure {
                    statusCard(icon: "exclamationmark.triangle", title: "暂时无法连接", message: failure, color: .orange)
                } else if receiver.isStarting {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("正在准备 Mac 接收器…").foregroundStyle(Palette.muted)
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
                }
                if let state = receiver.state {
                    connectionStatus(state)
                    pairingCard(state)
                }
                actions
                Text("保持此窗口打开。手机与 Mac 需要连接同一网络。\n二维码和配对链接可以控制这台 Mac，请勿分享。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(5)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .foregroundStyle(.white)
        .tint(Palette.mint)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 29, weight: .semibold)).foregroundStyle(Palette.background)
                .frame(width: 60, height: 60).background(Palette.mint, in: RoundedRectangle(cornerRadius: 19))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Sofatap").font(.system(size: 29, weight: .bold, design: .rounded))
                Text("把 iPhone 变成你的 Mac 遥控器")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func connectionStatus(_ state: ReceiverState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(state.connected ? Palette.mint : Palette.muted).frame(width: 8, height: 8)
                Text(state.connected ? "手机已连接" : "等待手机连接").font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            if state.dryRun || state.inputStatus == "dry_run" {
                statusCard(icon: "testtube.2", title: "演练模式", message: "连接可用，但不会向 Mac 提交鼠标或键盘操作。", color: .orange)
            } else if state.inputStatus == "accessibility_required" {
                VStack(alignment: .leading, spacing: 14) {
                    Label("允许 Sofatap 操作 Mac", systemImage: "hand.raised").font(.system(size: 15, weight: .semibold))
                    Text(receiver.accessNotice ?? "点下方按钮请求辅助功能授权。允许 Sofatap Receiver 后，接收器会自动重新检查。")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(receiver.accessRequested ? "再次请求授权" : "请求辅助功能授权", action: receiver.requestAccess)
                            .buttonStyle(.borderedProminent).foregroundStyle(Palette.background)
                        Button("打开系统设置", action: receiver.openAccessibilitySettings).buttonStyle(.bordered)
                    }.controlSize(.large)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
            } else if state.inputStatus != "ready" {
                statusCard(icon: "lock.display", title: "Mac 桌面暂时不可用", message: "请登录并解锁这台 Mac，再重新检查。", color: .orange)
            } else {
                Label("桌面已就绪", systemImage: "checkmark.shield")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
        }
    }

    private func pairingCard(_ state: ReceiverState) -> some View {
        VStack(alignment: .center, spacing: 16) {
            Text("扫码，坐回沙发").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("在 iPhone 打开 Sofatap → 配对电脑 → 扫码")
                .font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let pairing = receiver.selectedPairing, let data = pairing.pngData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                    .frame(width: 224, height: 224).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("用 iPhone 的 Sofatap 扫描此二维码以配对 Mac")
                Text(state.name).font(.system(size: 14, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                if state.pairings.count > 1 {
                    Picker("连接地址", selection: $receiver.selectedHost) {
                        ForEach(state.pairings) { address in Text(address.host).tag(Optional(address.host)) }
                    }.pickerStyle(.menu).frame(maxWidth: 300)
                    Text("有多个网络时，请选择手机能访问的地址。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                } else {
                    Text(pairing.host).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                Button(action: receiver.copyPairing) {
                    Label(receiver.copied ? "已复制配对链接" : "复制配对链接", systemImage: receiver.copied ? "checkmark" : "doc.on.doc")
                }.buttonStyle(.bordered)
            } else {
                Image(systemName: "wifi.slash").font(.system(size: 32)).foregroundStyle(Palette.muted).padding(.top, 12)
                Text(state.pairings.isEmpty ? "没有可配对的网络地址。连接 Wi-Fi 或网线后重新检查。" : "无法显示二维码，请重新检查。")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 12)
            }
        }
        .padding(24).frame(maxWidth: .infinity).background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
    }

    private func statusCard(icon: String, title: String, message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(message).font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: receiver.refresh) { Label("重新检查", systemImage: "arrow.clockwise") }
                .disabled(receiver.isStarting || receiver.isStopping)
            Spacer(minLength: 0)
            Button("退出 Sofatap") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
                .disabled(receiver.isStopping)
        }.buttonStyle(.bordered).controlSize(.large)
    }
}
