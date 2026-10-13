import SwiftUI
import UIKit

struct RemoteView: View {
    // Xcode uses the asset catalog; the direct compiler fallback bundles the
    // same PNG as a resource, which SwiftUI's named-image lookup does not read.
    private static let brandImage: UIImage = {
        if let image = UIImage(named: "BrandMark") { return image }
        if let path = Bundle.main.path(forResource: "BrandMark", ofType: "png"),
           let image = UIImage(contentsOfFile: path) { return image }
        return UIImage(systemName: "sofa.fill") ?? UIImage()
    }()
    @ObservedObject var model: ControllerModel
    @ObservedObject private var unlock: ComputerUnlockController
    init(model: ControllerModel) { self.model = model; self.unlock = model.unlock }
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dictation = SpeechDictationController()
    @State private var pairingSheet = false
    @State private var statusSheet = false
    @State private var showingSpeechError = false
    @State private var touchControl = TouchSurface.Control()
    @State private var resendAlert = false
    @State private var clearAlert = false
    @State private var composerVisible = false
    @State private var keyboardFocused = false
    @State private var handledFocusRevision: Int?
    @State private var speechBaseDraft = ""
    @State private var speechBaseSnapshot: LiveTextSnapshot?
    @State private var speechRequest: UUID?
    @State private var speechOwnsDraft = false
    @State private var dictationStartTask: Task<Void, Never>?

    private var speechBusy: Bool { dictation.state != .idle }
    private var inputEnabled: Bool {
        model.canControl && scenePhase == .active && !pairingSheet && !statusSheet &&
        !showingSpeechError && !resendAlert && !clearAlert
    }

    var body: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.height - 32)
            let padMinimum = min(184, available * 0.62)
            VStack(spacing: 12) {
                touchpad
                    .frame(maxWidth: .infinity, minHeight: padMinimum, maxHeight: .infinity)
                    .layoutPriority(1)
                if composerVisible {
                    ScrollView {
                        composer(height: geometry.size.height < 500 ? 52 : 92)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(208, available - padMinimum))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Palette.background)
        .sheet(isPresented: $pairingSheet) { PairingView(model: model) }
        .sheet(isPresented: $statusSheet) { statusDetails }
        .alert("语音输入暂不可用", isPresented: $showingSpeechError) {
            Button("使用键盘") { toggleKeyboard() }
            Button("好", role: .cancel) {}
        } message: { Text(dictation.errorMessage ?? "请尝试键盘或 Typeless。") }
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
        .onChange(of: model.liveTextStatus) { _, _ in
            if model.liveTextPaused || (model.usesLiveText && model.liveTextStatus == .idle && speechRequest != nil) {
                cancelSpeech()
            }
        }
        .onChange(of: model.dragging) { _, dragging in
            if !dragging { applyRemoteFocus() }
        }
        .onChange(of: model.canControl) { _, enabled in
            if enabled { applyRemoteFocus() }
        }
        .onChange(of: model.controlAvailable) { _, available in
            // A pending drag release blocks new input without disconnecting or
            // stopping dictation. Only session/permission loss resets UI state.
            if !available { handledFocusRevision = nil; stopInteraction() }
        }
        .onChange(of: pairingSheet) { _, shown in
            if shown { stopInteraction() }
            else { applyRemoteFocus() }
        }
        .onChange(of: statusSheet) { _, shown in
            if shown { stopInteraction() }
            else { applyRemoteFocus() }
        }
        .onChange(of: model.pairingError) { _, error in
            if error != nil && !pairingSheet { interruptTouch(); statusSheet = true }
        }
        .onChange(of: dictation.errorMessage) { _, error in
            if error != nil { interruptTouch(); showingSpeechError = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopInteraction() }
            else if phase == .inactive {
                interruptTouch()
                keyboardFocused = false
                if dictation.state != .requestingPermission { cancelSpeech() }
            } else { applyRemoteFocus() }
        }
        .onReceive(dictation.$transcript) { transcript in
            // @Published replays its current value when SwiftUI subscribes. Ignore
            // an idle session's previous result and a new session's empty reset.
            guard let draft = DictationTranscript.draft(base: speechBaseDraft, transcript: transcript,
                                                       ownsDraft: speechOwnsDraft,
                                                       sessionIsActive: dictation.state != .idle) else { return }
            if let base = speechBaseSnapshot {
                guard let snapshot = base.replacingSelection(with: transcript) else { return }
                model.editText(snapshot.text, selection: snapshot.selection, marked: false)
            } else { model.draft = draft }
        }
        .onChange(of: dictation.state) { _, state in
            if state == .idle { speechOwnsDraft = false; speechRequest = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                stopInteraction()
                statusSheet = true
            } label: {
                Image(uiImage: Self.brandImage)
                    .resizable().scaledToFit()
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: statusSymbol)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.background)
                            .frame(width: 16, height: 16)
                            .background(statusColor, in: Circle())
                            .overlay(Circle().stroke(Palette.background, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sofatap，连接状态与帮助")
            .accessibilityValue(model.statusTitle)
            .accessibilityIdentifier("connectionStatus")
            Spacer(minLength: 8)
            Button {
                stopInteraction()
                pairingSheet = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .foregroundStyle(Palette.mint.opacity(0.88))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("配对电脑与连接设置")
            .accessibilityIdentifier("pairingButton")
        }
    }

    private var touchpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.064, green: 0.095, blue: 0.104),
                                               Color(red: 0.032, green: 0.048, blue: 0.059)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
            TouchSurface(enabled: inputEnabled, control: touchControl,
                         onMove: { model.move(dx: $0, dy: $1) },
                         onLeftTap: { model.click("left") },
                         onRightTap: { model.click("right") },
                         onDraggingChanged: { model.setDragging($0) },
                         onScroll: { model.scroll(dy: $0) })
        }
        .overlay {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Palette.mint.opacity(0.24), Palette.mint.opacity(0.045), Palette.mint.opacity(0.13)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { header.padding(.horizontal, 20).padding(.top, 20) }
        .overlay(alignment: .bottom) { bottomBar.padding(.horizontal, 20).padding(.bottom, 20) }
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
    }

    private var bottomBar: some View {
        HStack(spacing: 13) {
            Button { toggleKeyboard() } label: {
                Image(systemName: keyboardFocused ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 20)).frame(width: 48, height: 52)
                    .contentShape(Rectangle())
                    .foregroundStyle(Palette.mint.opacity(keyboardFocused ? 1 : 0.65))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(keyboardFocused ? "收起键盘" : "打开键盘输入")
            .accessibilityIdentifier("keyboardButton")
            Spacer(minLength: 0)
            Button { toggleDictation() } label: {
                ZStack {
                    Circle().fill(dictation.isRecording ? Color(red: 0.99, green: 0.64, blue: 0.47) : Palette.mint)
                    Circle().stroke(Palette.mint.opacity(0.18), lineWidth: 1).padding(-6)
                    if dictation.state == .requestingPermission || dictation.state == .finishing || (speechRequest != nil && model.editorLoading) {
                        ProgressView().tint(Palette.background)
                    } else {
                        Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: dictation.isRecording ? 19 : 25, weight: .medium))
                    }
                }
                .frame(width: 64, height: 64)
                .contentShape(Circle())
                .foregroundStyle(Palette.background)
                .shadow(color: Palette.mint.opacity(0.13), radius: 18, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(!model.controlAvailable || model.sendingText || model.composing || model.remoteTextFocus == .protected)
            .opacity(model.controlAvailable ? 1 : 0.45)
            .accessibilityLabel(dictation.isRecording ? "结束听写" : speechBusy || speechRequest != nil ? "取消语音输入" : "开始语音输入")
            .accessibilityValue(dictation.isRecording ? "麦克风正在录音" : dictation.state == .finishing ? "正在整理听写结果" : "")
            .accessibilityIdentifier("dictationButton")
            Spacer(minLength: 0)
            Color.clear.frame(width: 48, height: 52).allowsHitTesting(false)
        }
    }

    private var statusSymbol: String {
        if model.pairingError != nil { return "exclamationmark" }
        if model.demo { return "play.fill" }
        if model.connecting { return "ellipsis" }
        if model.canControl { return "checkmark" }
        return model.connected ? "pause.fill" : "link"
    }

    private var statusColor: Color {
        if model.pairingError != nil || model.demo || (model.connected && !model.inputAvailable) { return .orange }
        return model.canControl ? Palette.mint : Palette.muted
    }

    private var statusDetails: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(model.statusTitle, systemImage: statusSymbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(statusColor)
                        Text(model.notice).foregroundStyle(Palette.muted)
                        if let error = model.pairingError {
                            Text(error).foregroundStyle(.orange)
                        }
                    }
                    if unlock.savedBinding != nil {
                        LegacyUnlockCredentialRemovalView(unlock: unlock)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Label("滑动手指，移动电脑光标", systemImage: "hand.draw")
                        Label("单击左键，连续点两下右键", systemImage: "hand.tap")
                        Label("按住 0.3 秒开始拖动，抬手松开", systemImage: "hand.point.up")
                        Label("双指滑动，滚动页面", systemImage: "hand.draw.fill")
                        Label("点麦克风听写，文字自动同步到电脑", systemImage: "mic")
                    }
                    .font(.body)
                    Text("光效跟随你在手机上的手指，电脑光标的位置请看电脑屏幕。")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Palette.background)
            .navigationTitle("Sofatap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { statusSheet = false } } }
        }
        .tint(Palette.mint)
    }

    private func composer(height: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if model.draft.isEmpty {
                    Text(dictation.isRecording ? "正在听…" : model.usesLiveText ? "输入或听写，自动同步到电脑" : "输入或听写，确认后发送到电脑")
                        .font(.system(size: 16)).foregroundStyle(Palette.muted.opacity(0.7))
                        .padding(14).allowsHitTesting(false)
                }
                NativeDraftEditor(text: $model.draft, composing: $model.composing,
                                  isFocused: $keyboardFocused,
                                  disabled: model.sendingText || speechBusy || model.editorLoading || (model.usesLiveText && !model.liveTextReady) || (!model.usesLiveText && model.textDelivery == .sent),
                                  selection: model.usesLiveText ? $model.draftSelection : nil,
                                  onEdit: { text, selection, marked in model.editText(text, selection: selection, marked: marked) },
                                  preservesFocusWhileLoading: model.editorLoading,
                                  liveEditing: model.usesLiveText)
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
                if !model.usesLiveText {
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
            }
            if model.liveTextPaused {
                Button("检查电脑后重新读取输入框") { model.restartLiveTextEditing() }
                    .font(.system(size: 11, weight: .medium)).frame(minHeight: 44)
                    .accessibilityIdentifier("resumeLiveText")
            }
            if !model.usesLiveText && (model.textDelivery == .uncertain || model.textDelivery == .sent) {
                Button("检查电脑后允许重发") { interruptTouch(); resendAlert = true }
                    .font(.system(size: 11, weight: .medium))
                    .frame(minHeight: 44)
            }
            HStack {
                Button(model.usesLiveText ? "全选" : "清空草稿") {
                    if model.usesLiveText { model.selectAll(); keyboardFocused = true }
                    else { interruptTouch(); clearAlert = true }
                }
                    .accessibilityIdentifier(model.usesLiveText ? "selectAllText" : "clearTextDraft")
                    .disabled(model.draft.isEmpty || model.composing || model.sendingText || speechBusy || (model.usesLiveText && !model.liveTextReady))
                    .frame(minHeight: 44)
                Spacer()
                Text("\(model.draftLength) / 16,000")
                    .foregroundStyle(model.draftWithinLimit ? Palette.muted : .orange)
                Button("收起") {
                    keyboardFocused = false
                    cancelSpeech()
                    composerVisible = false
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var composerStatus: String {
        if dictation.isRecording { return model.usesLiveText ? "正在听写并实时同步…" : "正在听写，结束后确认文字再发送。" }
        if dictation.state == .finishing { return "正在整理听写结果…" }
        if model.remoteTextFocus == .protected { return "电脑当前为安全输入框，不会自动听写。" }
        if model.demo && model.textDelivery == .sent { return "演示反馈：文字没有发送到电脑。" }
        return model.textStatus
    }

    private func toggleKeyboard() {
        interruptTouch()
        cancelSpeech()
        if keyboardFocused { keyboardFocused = false; composerVisible = false }
        else {
            prepareNewComposition()
            composerVisible = true
            keyboardFocused = true
            model.openTextEditor()
        }
    }
    private func toggleDictation() {
        guard model.controlAvailable, !model.sendingText, !model.composing, model.remoteTextFocus != .protected else { return }
        interruptTouch()
        if dictation.isRecording { dictation.stop(); return }
        if speechBusy || speechRequest != nil { cancelSpeech(); return }
        keyboardFocused = false
        composerVisible = true
        prepareNewComposition()
        let request = UUID(); speechRequest = request
        model.openTextEditor {
            guard speechRequest == request, model.controlAvailable, scenePhase == .active else { return }
            speechBaseDraft = model.draft
            speechBaseSnapshot = model.liveTextReady ? LiveTextSnapshot(text: model.draft, selection: model.draftSelection) : nil
            speechOwnsDraft = true
            dictationStartTask?.cancel()
            dictationStartTask = Task {
                guard !Task.isCancelled, speechRequest == request, model.controlAvailable, scenePhase == .active else { return }
                await dictation.start()
            }
        }
    }
    private func applyRemoteFocus() {
        guard model.canControl, scenePhase == .active, !pairingSheet, !statusSheet, !showingSpeechError,
              !resendAlert, !clearAlert,
              handledFocusRevision != model.focusRevision else { return }
        // A desktop field may become focused while the user is selecting text.
        // Wait for mouse-up before opening a keyboard and resizing the pad.
        if model.remoteTextFocus == .editable && model.dragging { return }
        handledFocusRevision = model.focusRevision
        switch model.remoteTextFocus {
        case .editable:
            guard !speechBusy else { return }
            interruptTouch()
            prepareNewComposition()
            composerVisible = true
            keyboardFocused = true
            model.openTextEditor()
        case .other, .protected:
            keyboardFocused = false
            cancelSpeech()
        case .unknown:
            break // Unsupported desktop focus detection leaves manual input available.
        }
    }
    private func stopInteraction() {
        interruptTouch()
        keyboardFocused = false
        cancelSpeech()
        model.endLiveTextEditing()
    }
    private func cancelSpeech() {
        speechRequest = nil
        dictationStartTask?.cancel()
        dictation.cancel()
        speechOwnsDraft = false
    }
    private func interruptTouch() {
        touchControl.cancel()
        model.pauseInput()
    }
    private func prepareNewComposition() {
        // A confirmed previous delivery is a receipt, not a prefix for the next
        // utterance. Unsent and uncertain drafts always remain available.
        if !model.usesLiveText && model.textDelivery == .sent { model.clearDraft() }
    }
}

#Preview { RemoteView(model: ControllerModel(demo: true)).preferredColorScheme(.dark) }
