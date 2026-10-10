import SwiftUI

enum RemoteMode: String, CaseIterable { case touch = "触控板", air = "空中鼠标", text = "文字" }

struct RemoteView: View {
    @ObservedObject var model: ControllerModel
    @State private var mode: RemoteMode = .touch
    @State private var pairingSheet = false
    @State private var resendAlert = false
    @State private var clearAlert = false
    @State private var scrollOffset = 0.0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    connection
                    if let error = model.pairingError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("配对未保存", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 14, weight: .semibold))
                            Text(error).font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                            Button("查看配对设置") { pairingSheet = true }
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.orange)
                        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("pairingErrorBanner")
                    }
                    Picker("控制方式", selection: $mode) {
                        ForEach(RemoteMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("remoteMode")
                    if mode == .text { textPanel }
                    else {
                        if mode == .touch { touchpad(height: max(220, min(330, geometry.size.height * 0.39))) }
                        else { airMouse(height: max(220, min(330, geometry.size.height * 0.39))) }
                        mouseButtons
                        shortcuts
                        sensitivity
                    }
                    Text(model.notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("connectionNotice")
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Palette.background)
        .sheet(isPresented: $pairingSheet) { PairingView(model: model) }
        .alert("允许再次发送这段文字？", isPresented: $resendAlert) {
            Button("取消", role: .cancel) {}
            Button("已查看电视，允许重发") { model.allowManualResend() }
        } message: {
            Text("上一次的文字可能已经输入。请先检查电视，再手动按发送；重复文字无法自动撤销。")
        }
        .alert("清空手机上的草稿？", isPresented: $clearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空草稿", role: .destructive) { model.clearDraft() }
        } message: { Text("不会删除电脑里已经输入的文字。") }
        .onChange(of: mode) { _, _ in model.stopAirMouse(); model.setDragging(false) }
        .onAppear { model.becameActive() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tiltro")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-0.7)
                Text("坐下来，电脑在手上。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Button { pairingSheet = true } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 50, height: 50)
                    .foregroundStyle(Palette.mint)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 17))
            }
            .accessibilityLabel("配对电脑与连接设置")
        }
    }

    private var connection: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(model.demo ? Color.orange : model.connected ? Palette.mint : Palette.muted)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.statusTitle).font(.system(size: 14, weight: .semibold))
                    .accessibilityIdentifier("connectionStatus")
                Text(model.statusSubtitle).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if !model.demo {
                if model.connecting { ProgressView().tint(Palette.mint) }
                else if model.connected {
                    Button("断开") { model.disconnect() }.font(.footnote.weight(.medium))
                } else {
                    Button(model.pairing == nil ? "配对" : "连接") {
                        if model.pairing == nil { pairingSheet = true } else { model.connect() }
                    }.font(.footnote.weight(.semibold))
                }
            } else {
                Image(systemName: "eye").foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private func touchpad(height: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Palette.panel.gradient)
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Palette.mint.opacity(model.dragging ? 0.65 : 0.10), lineWidth: 1)
            VStack(spacing: 16) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundStyle(Palette.mint.opacity(0.8))
                VStack(spacing: 7) {
                    Text(model.dragging ? "拖动中" : "在这里滑动")
                        .font(.system(size: 22, weight: .medium))
                    Text("移动光标  ·  轻点单击")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
            }
            .allowsHitTesting(false)
            TouchSurface(enabled: model.canControl,
                         onMove: { model.move(dx: $0, dy: $1) }, onTap: { model.click("left") })
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
                    Text("滚\n动").font(.system(size: 11, weight: .medium)).lineSpacing(4)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Palette.muted)
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .background(Palette.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let current = value.translation.height
                        model.scroll(dy: -(current - scrollOffset))
                        scrollOffset = current
                    }
                    .onEnded { _ in scrollOffset = 0 })
                .accessibilityLabel("上下滑动滚动电脑页面")
            }
            .padding(12)
        }
        .frame(height: height)
        .opacity(model.canControl ? 1 : 0.55)
    }

    private func airMouse(height: Double) -> some View {
        HoldControl(enabled: model.canControl, onPress: model.startAirMouse, onRelease: model.stopAirMouse) {
            VStack(spacing: 20) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 52, weight: .ultraLight))
                    .symbolEffect(.pulse, isActive: model.airMoving)
                VStack(spacing: 8) {
                    Text(model.airMoving ? "转动手机，移动光标" : "按住，轻轻转动")
                        .font(.system(size: 21, weight: .medium))
                    Text("松手暂停  ·  手回到舒服的位置再按住")
                        .font(.system(size: 11))
                        .foregroundStyle(model.airMoving ? Palette.background.opacity(0.7) : Palette.muted)
                }
            }
            .foregroundStyle(model.airMoving ? Palette.background : Palette.mint)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(model.airMoving ? Palette.mint : Palette.panel, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Palette.mint.opacity(0.18)))
        }
        .accessibilityLabel("按住启用空中鼠标，松开归位")
        .opacity(model.canControl ? 1 : 0.55)
    }

    private var mouseButtons: some View {
        HStack(spacing: 10) {
            mouseButton("左键", icon: "cursorarrow", action: { model.click("left") })
            HoldControl(enabled: model.canControl, onPress: { model.setDragging(true) }, onRelease: { model.setDragging(false) }) {
                VStack(spacing: 8) {
                    Image(systemName: "hand.point.up.left").font(.system(size: 21, weight: .regular))
                    Text(model.dragging ? "松开结束" : "按住拖拽").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(model.dragging ? Palette.background : .white)
                .frame(maxWidth: .infinity).frame(height: 78)
                .background(model.dragging ? Palette.mint : Palette.elevated, in: RoundedRectangle(cornerRadius: 20))
            }
            .opacity(model.canControl ? 1 : 0.45)
            mouseButton("右键", icon: "computermouse", action: { model.click("right") })
        }
    }

    private func mouseButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 21, weight: .regular))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity).frame(height: 78)
            .foregroundStyle(.white)
            .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 20))
        }
        .disabled(!model.canControl)
        .opacity(model.canControl ? 1 : 0.45)
    }

    private var shortcuts: some View {
        HStack(spacing: 9) {
            keyButton("Esc", key: "escape")
            keyButton("Tab", key: "tab")
            keyButton("退格", key: "backspace")
            keyButton("Enter", key: "enter")
        }
    }

    private func keyButton(_ label: String, key: String) -> some View {
        Button { model.key(key) } label: {
            Text(label).font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity).frame(height: 43)
                .foregroundStyle(Palette.muted)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 13))
        }
        .disabled(!model.canControl)
    }

    private var sensitivity: some View {
        HStack(spacing: 13) {
            Image(systemName: "speedometer").foregroundStyle(Palette.muted)
            Slider(value: $model.sensitivity, in: 0.3...2.5)
                .accessibilityLabel("鼠标灵敏度")
            Text(String(format: "%.1f×", model.sensitivity))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                .frame(width: 35)
        }
        .padding(.horizontal, 3)
    }

    private var textPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 7) {
                Text("说完，再发到电脑")
                    .font(.system(size: 23, weight: .medium))
                Text("使用 iPhone 原生键盘、系统听写或 Typeless。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            ZStack(alignment: .topLeading) {
                if model.draft.isEmpty {
                    Text("点这里，开始输入或语音听写…")
                        .font(.system(size: 20)).foregroundStyle(Palette.muted.opacity(0.65))
                        .padding(.horizontal, 17).padding(.vertical, 17)
                        .allowsHitTesting(false)
                }
                NativeDraftEditor(text: $model.draft, composing: $model.composing, disabled: model.sendingText)
            }
            .frame(minHeight: 220, maxHeight: 280)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.mint.opacity(0.15)))
            HStack {
                Label("仅保存在这台手机", systemImage: "lock")
                Spacer()
                Text("\(model.draftLength) / 16,000")
                    .foregroundStyle(model.draftWithinLimit ? Palette.muted : .orange)
            }
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
            Button(action: model.sendText) {
                HStack(spacing: 10) {
                    if model.sendingText { ProgressView().tint(Palette.background) }
                    else { Image(systemName: model.textDelivery == .sent ? "checkmark" : "arrow.up.right") }
                    Text(model.sendingText ? "等待电脑确认" : model.textDelivery == .sent ? "已发送" : "发送整段文字")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity).frame(height: 58)
                .foregroundStyle(Palette.background)
                .background(Palette.mint, in: RoundedRectangle(cornerRadius: 19))
            }
            .disabled(!model.canSendText)
            .opacity(model.canSendText || model.sendingText || model.textDelivery == .sent ? 1 : 0.4)
            .accessibilityIdentifier("sendText")
            Text(model.demo && model.textDelivery == .sent ? "演示反馈：文字没有发送到电脑。" : model.textStatus)
                .font(.system(size: 12)).foregroundStyle(model.textDelivery == .uncertain ? Color.orange : Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("清空草稿") { clearAlert = true }
                    .disabled(model.draft.isEmpty || model.sendingText)
                Spacer()
                if model.textDelivery == .uncertain || model.textDelivery == .sent {
                    Button("检查后允许重发") { resendAlert = true }
                }
            }
            .font(.system(size: 12, weight: .medium))
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "info.circle")
                Text("发送不会自动按 Enter。语音键盘跳转 App 时会暂停连接，返回后草稿仍在。")
            }
            .font(.system(size: 11)).foregroundStyle(Palette.muted)
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

#Preview { RemoteView(model: ControllerModel(demo: true)).preferredColorScheme(.dark) }
