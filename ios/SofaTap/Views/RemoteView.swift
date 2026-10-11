import SwiftUI

struct RemoteView: View {
    @ObservedObject var model: ControllerModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dictation = SpeechDictationController()
    @State private var pairingSheet = false
    @State private var resendAlert = false
    @State private var clearAlert = false
    @State private var composerVisible = false
    @State private var keyboardFocused = false
    @State private var handledFocusRevision: Int?
    @State private var speechBaseDraft = ""
    @State private var speechOwnsDraft = false
    @State private var dictationStartTask: Task<Void, Never>?

    private var speechBusy: Bool { dictation.state != .idle }
    private var inputEnabled: Bool { model.canControl && scenePhase == .active && !pairingSheet }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                header
                if let error = model.pairingError {
                    Button { pairingSheet = true } label: {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote).multilineTextAlignment(.leading)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("pairingErrorBanner")
                }
                touchpad
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                if composerVisible { composer(height: min(108, max(68, geometry.size.height * 0.18))) }
                bottomBar
                if let error = dictation.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dictationError")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Palette.background)
        .sheet(isPresented: $pairingSheet) { PairingView(model: model) }
        .alert("允许再次发送这段文字？", isPresented: $resendAlert) {
            Button("取消", role: .cancel) {}
            Button("已查看屏幕，允许重发") { model.allowManualResend() }
        } message: {
            Text("上一次的文字可能已经输入。请先检查电脑屏幕，再手动按发送；重复文字无法自动撤销。")
        }
        .alert("清空手机上的草稿？", isPresented: $clearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空草稿", role: .destructive) { model.clearDraft() }
        } message: { Text("不会删除电脑里已经输入的文字。") }
        .onAppear {
            model.becameActive()
            if model.textDelivery == .uncertain { composerVisible = true }
            applyRemoteFocus()
        }
        .onDisappear { stopInteraction() }
        .onChange(of: model.focusRevision) { _, _ in applyRemoteFocus() }
        .onChange(of: model.canControl) { _, enabled in
            if enabled { applyRemoteFocus() }
            else { handledFocusRevision = nil; stopInteraction() }
        }
        .onChange(of: pairingSheet) { _, shown in
            if shown { stopInteraction() }
            else { applyRemoteFocus() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopInteraction() }
            else if phase == .inactive {
                model.setDragging(false)
                keyboardFocused = false
                if dictation.state != .requestingPermission { dictation.cancel() }
            } else { applyRemoteFocus() }
        }
        .onReceive(dictation.$transcript) { transcript in
            guard speechOwnsDraft else { return }
            let separator = speechBaseDraft.isEmpty || speechBaseDraft.last?.isWhitespace == true || transcript.isEmpty ? "" : "\n"
            model.draft = speechBaseDraft + separator + transcript
        }
        .onChange(of: dictation.state) { _, state in
            if state == .idle { speechOwnsDraft = false }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sofatap")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .tracking(-0.4)
                HStack(spacing: 6) {
                    Circle().fill(model.demo ? Color.orange : model.connected ? Palette.mint : Palette.muted)
                        .frame(width: 6, height: 6)
                    Text(model.statusTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted).lineLimit(1)
                        .accessibilityIdentifier("connectionStatus")
                    if model.connecting { ProgressView().controlSize(.mini).tint(Palette.mint) }
                }
            }
            Spacer(minLength: 8)
            Button {
                pairingSheet = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Palette.mint)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("配对电脑与连接设置")
        }
    }

    private var touchpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 27).fill(Palette.panel.gradient)
            RoundedRectangle(cornerRadius: 27)
                .strokeBorder(Palette.mint.opacity(model.dragging ? 0.65 : 0.12), lineWidth: 1)
            VStack(spacing: 13) {
                Spacer(minLength: 8)
                Image(systemName: model.dragging ? "hand.draw" : "cursorarrow")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(Palette.mint.opacity(0.8))
                Text(model.dragging ? "拖动中 · 松手结束" : "滑动，移动光标")
                    .font(.system(size: 19, weight: .medium))
                if !model.canControl {
                    Text(model.notice)
                        .font(.caption).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center).lineLimit(3)
                        .padding(.horizontal, 25)
                        .accessibilityIdentifier("connectionNotice")
                }
                Spacer(minLength: 8)
                Text("轻点左键 · 连点两下右键\n按住 0.3 秒拖动 · 双指滑动滚动")
                    .font(.system(size: 11)).lineSpacing(5)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
            }
            .allowsHitTesting(false)
            TouchSurface(enabled: inputEnabled,
                         onMove: { model.move(dx: $0, dy: $1) },
                         onLeftTap: { model.click("left") },
                         onRightTap: { model.click("right") },
                         onDraggingChanged: { model.setDragging($0) },
                         onScroll: { model.scroll(dy: $0) })
                .clipShape(RoundedRectangle(cornerRadius: 27))
        }
        .opacity(model.canControl ? 1 : 0.55)
    }

    private var bottomBar: some View {
        HStack(spacing: 13) {
            Button { toggleKeyboard() } label: {
                Image(systemName: keyboardFocused ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 21)).frame(width: 46, height: 48)
                    .foregroundStyle(Palette.muted)
            }
            .accessibilityLabel(keyboardFocused ? "收起键盘" : "打开键盘输入")
            .accessibilityIdentifier("keyboardButton")
            Spacer(minLength: 0)
            Button { toggleDictation() } label: {
                HStack(spacing: 9) {
                    if dictation.state == .requestingPermission || dictation.state == .finishing {
                        ProgressView().tint(Palette.background)
                    } else {
                        Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 20, weight: .medium))
                    }
                    Text(dictation.isRecording ? "结束听写" : dictation.state == .finishing ? "正在整理…" : "语音输入")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(minWidth: 144).frame(height: 50)
                .foregroundStyle(Palette.background)
                .background(Palette.mint, in: Capsule())
            }
            .disabled(!model.canControl || model.sendingText || model.composing || model.remoteTextFocus == .protected)
            .opacity(model.canControl ? 1 : 0.45)
            .accessibilityIdentifier("dictationButton")
            Spacer(minLength: 0)
            Color.clear.frame(width: 46, height: 48).allowsHitTesting(false)
        }
    }

    private func composer(height: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if model.draft.isEmpty {
                    Text(dictation.isRecording ? "正在听…" : "输入或听写，确认后发送到电脑")
                        .font(.system(size: 16)).foregroundStyle(Palette.muted.opacity(0.7))
                        .padding(14).allowsHitTesting(false)
                }
                NativeDraftEditor(text: $model.draft, composing: $model.composing,
                                  isFocused: $keyboardFocused,
                                  disabled: model.sendingText || speechBusy || model.textDelivery == .sent)
            }
            .frame(height: height)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 12) {
                Text(composerStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(model.textDelivery == .uncertain ? Color.orange : Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("textDeliveryStatus")
                Spacer(minLength: 0)
                Button(action: model.sendText) {
                    HStack(spacing: 6) {
                        if model.sendingText { ProgressView().tint(Palette.background) }
                        else { Image(systemName: model.textDelivery == .sent ? "checkmark" : "arrow.up") }
                        Text(model.sendingText ? "等待确认" : "发送")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 15).frame(height: 44)
                    .foregroundStyle(Palette.background)
                    .background(Palette.mint, in: Capsule())
                }
                .disabled(!model.canSendText || speechBusy)
                .opacity(model.canSendText && !speechBusy || model.sendingText ? 1 : 0.45)
                .accessibilityIdentifier("sendText")
            }
            if model.textDelivery == .uncertain || model.textDelivery == .sent {
                Button("检查电脑后允许重发") { resendAlert = true }
                    .font(.system(size: 11, weight: .medium))
                    .frame(minHeight: 44)
            }
            HStack {
                Button("清空草稿") { clearAlert = true }
                    .disabled(model.draft.isEmpty || model.sendingText || speechBusy)
                    .frame(minHeight: 44)
                Spacer()
                Text("\(model.draftLength) / 16,000")
                    .foregroundStyle(model.draftWithinLimit ? Palette.muted : .orange)
                Button("收起") {
                    keyboardFocused = false
                    dictationStartTask?.cancel()
                    dictation.cancel()
                    composerVisible = false
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var composerStatus: String {
        if dictation.isRecording { return "正在听写，结束后确认文字再发送。" }
        if dictation.state == .finishing { return "正在整理听写结果…" }
        if model.remoteTextFocus == .protected { return "电脑当前为安全输入框，不会自动听写。" }
        if model.demo && model.textDelivery == .sent { return "演示反馈：文字没有发送到电脑。" }
        return model.textStatus
    }

    private func toggleKeyboard() {
        dictationStartTask?.cancel()
        dictation.cancel()
        speechOwnsDraft = false
        if keyboardFocused { keyboardFocused = false; composerVisible = false }
        else {
            prepareNewComposition()
            composerVisible = true
            keyboardFocused = true
        }
    }
    private func toggleDictation() {
        guard model.canControl, !model.sendingText, !model.composing, model.remoteTextFocus != .protected else { return }
        if dictation.isRecording { dictation.stop(); return }
        if speechBusy { dictationStartTask?.cancel(); dictation.cancel(); return }
        keyboardFocused = false
        composerVisible = true
        prepareNewComposition()
        speechBaseDraft = model.draft
        speechOwnsDraft = true
        dictationStartTask?.cancel()
        dictationStartTask = Task {
            guard !Task.isCancelled, model.canControl, scenePhase == .active else { return }
            await dictation.start()
        }
    }
    private func applyRemoteFocus() {
        guard model.canControl, scenePhase == .active, !pairingSheet,
              handledFocusRevision != model.focusRevision else { return }
        handledFocusRevision = model.focusRevision
        switch model.remoteTextFocus {
        case .editable:
            guard !speechBusy else { return }
            prepareNewComposition()
            composerVisible = true
            keyboardFocused = true
        case .other, .protected:
            keyboardFocused = false
            if model.remoteTextFocus == .protected { dictationStartTask?.cancel(); dictation.cancel() }
        case .unknown:
            break // Unsupported desktop focus detection leaves manual input available.
        }
    }
    private func stopInteraction() {
        model.setDragging(false)
        model.stopAirMouse()
        keyboardFocused = false
        dictationStartTask?.cancel()
        dictation.cancel()
    }
    private func prepareNewComposition() {
        // A confirmed previous delivery is a receipt, not a prefix for the next
        // utterance. Unsent and uncertain drafts always remain available.
        if model.textDelivery == .sent { model.clearDraft() }
    }
}

#Preview { RemoteView(model: ControllerModel(demo: true)).preferredColorScheme(.dark) }
