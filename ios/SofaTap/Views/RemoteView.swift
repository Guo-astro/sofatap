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
    init(model: ControllerModel) {
        self.model = model; self.unlock = model.unlock
        _tv = StateObject(wrappedValue: WebOSTVController(enabled: !model.demo))
        _androidTV = StateObject(wrappedValue: AndroidTVController(enabled: !model.demo))
        _androidSelected = State(initialValue: !model.demo && UserDefaults.standard.string(forKey: "manualRemoteTarget") == "androidtv")
#if targetEnvironment(simulator)
        // Isolated layout fixtures never create a receiver connection.
        _composerVisible = State(initialValue: model.demo && ProcessInfo.processInfo.arguments.contains("--demo-composer"))
        _keyboardFocused = State(initialValue: model.demo && ProcessInfo.processInfo.arguments.contains("--demo-keyboard"))
#endif
    }
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dictation = SpeechDictationController()
    @StateObject private var tv: WebOSTVController
    @StateObject private var androidTV: AndroidTVController
    @State private var androidSelected: Bool
    @State private var pairingSheet = false
    @State private var statusSheet = false
    @State private var showingSpeechError = false
    @State private var touchControl = TouchSurface.Control()
    @State private var edgeScrollControl = EdgeScrollStrip.Control()
    @State private var draftEditorControl = NativeDraftEditor.Control()
    @State private var dictationImpact = UIImpactFeedbackGenerator(style: .light)
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
    private var televisionSelected: Bool { !model.desktopControlEnabled }
    private var androidTVSelected: Bool { televisionSelected && androidSelected }
    private var currentStatusTitle: String { androidTVSelected ? androidTV.title : televisionSelected ? tv.title : model.statusTitle }
    private var inputEnabled: Bool {
        (androidTVSelected ? androidTV.canControl : televisionSelected ? tv.canControl : model.canControl) && scenePhase == .active && !pairingSheet && !statusSheet &&
        !showingSpeechError && !resendAlert && !clearAlert
    }

    var body: some View { dictationEvents }

    // Keep each opaque view expression small enough for the CI Swift compiler.
    // The modifier order remains layout -> presentation -> lifecycle -> dictation.
    private var layout: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                touchpad
                    .frame(maxWidth: .infinity, minHeight: min(170, geometry.size.height * 0.4), maxHeight: .infinity)
                if composerVisible && !televisionSelected {
                    composer(height: geometry.size.height < 500 ? 64 : 92)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background(Palette.background)
    }

    private var presentation: some View {
        layout
        .sheet(isPresented: $pairingSheet) {
            PairingView(model: model, tv: tv, androidTV: androidTV, selectAndroidTV: selectAndroidTelevision,
                        selectTV: selectTelevision, selectComputer: selectComputer)
        }
        .sheet(isPresented: $statusSheet) { statusDetails }
        .alert(String(localized: "语音输入暂不可用"), isPresented: $showingSpeechError) {
            Button(String(localized: "使用键盘")) { toggleKeyboard() }
            Button(String(localized: "好"), role: .cancel) {}
        } message: { Text(dictation.errorMessage ?? String(localized: "请尝试键盘或 Typeless。")) }
        .alert(String(localized: "允许再次发送这段文字？"), isPresented: $resendAlert) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "已查看屏幕，允许重发")) { model.allowManualResend() }
        } message: {
            Text(String(localized: "上一次的文字可能已经输入。请先检查电脑屏幕，再手动按发送；重复文字无法自动撤销。"))
        }
        .alert(model.usesLiveText ? String(localized: "清空电脑当前输入框？") : String(localized: "清空手机上的草稿？"), isPresented: $clearAlert) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "清空草稿"), role: .destructive) { model.clearDraft() }
        } message: {
            Text(model.usesLiveText ? String(localized: "这会同步删除当前输入框中的文字。") : String(localized: "不会删除电脑里已经输入的文字。"))
        }
    }

    private var connectionEvents: some View {
        presentation
        .onAppear {
            model.becameActive()
            if model.textDelivery == .uncertain { composerVisible = true }
            applyRemoteFocus()
        }
        .onDisappear { stopInteraction() }
        .onOpenURL { url in
            if (try? AndroidTVPairing.parse(url.absoluteString)) != nil {
                selectAndroidTelevision()
                androidTV.pair(url.absoluteString)
                statusSheet = true
                return
            }
            guard (try? Pairing.parse(url.absoluteString)) != nil else { model.acceptPairing(url.absoluteString); return }
            selectComputer()
            model.acceptPairing(url.absoluteString)
        }
        .onChange(of: model.focusRevision) { _, _ in applyRemoteFocus() }
        .onChange(of: model.desktopControlEnabled) { _, enabled in
            // Covers explicit computer pairing links delivered by the OS.
            stopInteraction()
            composerVisible = false
            handledFocusRevision = nil
            if enabled { tv.disconnect(); androidTV.disconnect() }
        }
        .onChange(of: androidTV.phase) { _, phase in
            if androidTVSelected && phase != .ready { touchControl.cancel() }
            if androidTVSelected && phase == .ready && scenePhase == .active && !pairingSheet && !statusSheet { androidTV.resumeInput() }
        }
        .onChange(of: androidTV.canControl) { _, available in
            if androidTVSelected && !available { touchControl.cancel() }
        }
        .onChange(of: tv.phase) { _, phase in
            if televisionSelected && !androidTVSelected && phase != .ready { touchControl.cancel() }
            if !androidTVSelected && phase == .ready && scenePhase == .active && !pairingSheet && !statusSheet { tv.resumeInput() }
        }
    }

    private var desktopEvents: some View {
        connectionEvents
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
            if !available && !televisionSelected { handledFocusRevision = nil; stopInteraction() }
        }
    }

    private var interactionEvents: some View {
        desktopEvents
        .onChange(of: pairingSheet) { _, shown in
            if shown { stopInteraction() }
            else { resumeCurrentInput() }
        }
        .onChange(of: statusSheet) { _, shown in
            if shown { stopInteraction() }
            else { resumeCurrentInput() }
        }
        .onChange(of: model.pairingError) { _, error in
            if !televisionSelected && error != nil && !pairingSheet { interruptTouch(); statusSheet = true }
        }
        .onChange(of: dictation.errorMessage) { _, error in
            if error != nil { interruptTouch(); showingSpeechError = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopInteraction(); tv.disconnect(); androidTV.disconnect() }
            else if phase == .inactive {
                interruptTouch()
                keyboardFocused = false
                if dictation.state != .requestingPermission { cancelSpeech() }
            } else { resumeCurrentInput() }
        }
    }

    private var dictationEvents: some View {
        interactionEvents
        .onReceive(dictation.$transcript) { transcript in
            guard !televisionSelected else { return }
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
            .accessibilityLabel(String(localized: "Sofatap，连接状态与帮助"))
            .accessibilityValue(currentStatusTitle)
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
            .accessibilityLabel(String(localized: "配对设备与连接设置"))
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
                         profile: televisionSelected ? .tvPointer : .desktop,
                         onMove: { dx, dy in
                             if androidTVSelected { androidTV.move(dx: dx, dy: dy) }
                             else if televisionSelected { tv.move(dx: dx, dy: dy) }
                             else { model.move(dx: dx, dy: dy) }
                         },
                         onLeftTap: { if androidTVSelected { androidTV.click() } else if televisionSelected { tv.click() } else { model.click("left") } },
                         onRightTap: { if !televisionSelected { model.click("right") } },
                         onDraggingChanged: { if !televisionSelected { model.setDragging($0) } },
                         onScroll: scrollCurrentDevice)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Palette.mint.opacity(0.24), Palette.mint.opacity(0.045), Palette.mint.opacity(0.13)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            EdgeScrollStrip(enabled: inputEnabled && (!androidTVSelected || androidTV.status?.capabilities.scroll == true),
                            control: edgeScrollControl,
                            interactionID: androidTVSelected ? "androidtv" : televisionSelected ? "webos" : "computer",
                            onInteractionBegan: { touchControl.cancel() },
                            onScroll: scrollCurrentDevice)
                .frame(width: EdgeScrollStrip.minimumHitWidth)
                // Keep the scroll target inside the pad and below the QR button.
                // The lower-right space is intentionally free of other controls.
                .padding(.top, 80)
                .padding(.bottom, 16)
                .padding(.trailing, 8)
        }
        .overlay(alignment: .top) { header.padding(.horizontal, 20).padding(.top, 20) }
        .overlay(alignment: .bottom) { bottomBar.padding(.horizontal, 20).padding(.bottom, 20) }
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
    }

    private var bottomBar: some View {
        Group {
            if televisionSelected {
                HStack {
                    Button { touchControl.cancel(); if androidTVSelected { androidTV.key(.back) } else { tv.button(.back) } } label: {
                        Image(systemName: "chevron.backward").frame(width: 52, height: 52)
                    }.accessibilityLabel(String(localized: "返回"))
                    Spacer()
                    Button { touchControl.cancel(); if androidTVSelected { androidTV.key(.home) } else { tv.button(.home) } } label: {
                        Image(systemName: "house").frame(width: 64, height: 64)
                    }.accessibilityLabel(String(localized: "电视主页"))
                    Spacer()
                    Color.clear.frame(width: 52, height: 52)
                }
                .font(.title2).foregroundStyle(Palette.mint)
                .buttonStyle(.plain).disabled(!inputEnabled)
            } else { computerBottomBar }
        }
    }

    private var computerBottomBar: some View {
        HStack(spacing: 13) {
            Button { toggleKeyboard() } label: {
                Image(systemName: keyboardFocused ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 20)).frame(width: 48, height: 52)
                    .contentShape(Rectangle())
                    .foregroundStyle(Palette.mint.opacity(keyboardFocused ? 1 : 0.65))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(keyboardFocused ? String(localized: "收起键盘") : String(localized: "打开键盘输入"))
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
            .buttonStyle(MicrophoneButtonStyle(prepareFeedback: { dictationImpact.prepare() }))
            .disabled(!model.controlAvailable || model.sendingText || model.composing || model.remoteTextFocus == .protected)
            .opacity(model.controlAvailable ? 1 : 0.45)
            .accessibilityLabel(dictation.isRecording ? String(localized: "结束听写") : speechBusy || speechRequest != nil ? String(localized: "取消语音输入") : String(localized: "开始语音输入"))
            .accessibilityValue(dictation.isRecording ? String(localized: "麦克风正在录音") : dictation.state == .finishing ? String(localized: "正在整理听写结果") : "")
            .accessibilityIdentifier("dictationButton")
            Spacer(minLength: 0)
            Color.clear.frame(width: 48, height: 52).allowsHitTesting(false)
        }
    }

    private var statusSymbol: String {
        if androidTVSelected {
            if androidTV.phase == .failed { return "exclamationmark" }
            return androidTV.canControl ? "checkmark" : androidTV.busy ? "ellipsis" : "tv"
        }
        if televisionSelected {
            if tv.phase == .failed { return "exclamationmark" }
            return tv.phase == .ready ? "checkmark" : tv.busy ? "ellipsis" : "tv"
        }
        if model.pairingError != nil { return "exclamationmark" }
        if model.demo { return "play.fill" }
        if model.connecting { return "ellipsis" }
        if model.canControl { return "checkmark" }
        return model.connected ? "pause.fill" : "link"
    }

    private var statusColor: Color {
        if androidTVSelected { return androidTV.phase == .failed ? .orange : androidTV.canControl ? Palette.mint : Palette.muted }
        if televisionSelected { return tv.phase == .failed ? .orange : tv.phase == .ready ? Palette.mint : Palette.muted }
        if model.pairingError != nil || model.demo || (model.connected && !model.inputAvailable) { return .orange }
        return model.canControl ? Palette.mint : Palette.muted
    }

    private var statusDetails: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(currentStatusTitle, systemImage: statusSymbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(statusColor)
                        Text(androidTVSelected ? androidTV.notice : televisionSelected ? tv.notice : model.notice).foregroundStyle(Palette.muted)
                        if !televisionSelected, let error = model.pairingError {
                            Text(error).foregroundStyle(.orange)
                        }
                    }
                    if unlock.savedBinding != nil {
                        LegacyUnlockCredentialRemovalView(unlock: unlock)
                    }
                    if televisionSelected {
                        if androidTVSelected {
                            Text(String(localized: "实验性接收端：光标是屏幕指示层，单击操作可访问控件，兼容性取决于电视与应用。暂不支持系统鼠标、右键、拖动、键盘或语音输入。"))
                        } else {
                            Text(String(localized: "滑动移动电视光标，单击选择，双指滚动。请在电视上确认操作结果。"))
                        }
                        Button(String(localized: "切回电脑遥控")) { selectComputer(); statusSheet = false }
                    } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(String(localized: "滑动手指，移动电脑光标"), systemImage: "hand.draw")
                        Label(String(localized: "单击左键，连续点两下右键"), systemImage: "hand.tap")
                        Label(String(localized: "按住 0.3 秒开始拖动，抬手松开"), systemImage: "hand.point.up")
                        Label(String(localized: "双指或右侧单指滑动，滚动页面"), systemImage: "hand.draw.fill")
                        Label(String(localized: "点麦克风听写；支持的输入框自动同步，其他输入框确认后发送"), systemImage: "mic")
                    }
                    .font(.body)
                    Text(String(localized: "光效跟随你在手机上的手指，电脑光标的位置请看电脑屏幕。"))
                        .font(.footnote).foregroundStyle(Palette.muted)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Link(String(localized: "隐私政策"), destination: URL(string: "https://github.com/chekusu/sofatap/blob/main/PRIVACY.md")!)
                        Link(String(localized: "帮助与反馈"), destination: URL(string: "https://github.com/chekusu/sofatap/issues")!)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Palette.background)
            .navigationTitle("Sofatap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "完成")) { statusSheet = false } } }
        }
        .tint(Palette.mint)
    }

    private func composer(height: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if model.draft.isEmpty {
                    Text(dictation.isRecording ? String(localized: "正在听…") : model.usesLiveText ? String(localized: "输入或听写，自动同步到电脑") : String(localized: "输入或听写，确认后发送到电脑"))
                        .font(.system(size: 16)).foregroundStyle(Palette.muted.opacity(0.7))
                        .padding(14).allowsHitTesting(false)
                }
                NativeDraftEditor(text: $model.draft, composing: $model.composing,
                                  isFocused: $keyboardFocused,
                                  disabled: speechBusy || model.editorLoading || (model.usesLiveText && !model.liveTextReady),
                                  selection: model.usesLiveText ? $model.draftSelection : nil,
                                  onEdit: { text, selection, marked in model.editText(text, selection: selection, marked: marked) },
                                  preservesFocusWhileLoading: model.editorLoading,
                                  liveEditing: model.usesLiveText,
                                  control: draftEditorControl)
            }
            .frame(height: height)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
            composerNotice
            composerActions
        }
    }

    private var composerNotice: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !model.usesLiveText {
                Text(fallbackInputNotice)
                    .accessibilityIdentifier("textInputCapability")
            }
            // Keep the capability notice visible during dictation and delivery.
            // Ordinary fallback instructions already appear in that notice.
            if model.usesLiveText || speechBusy || model.composing || !model.draftWithinLimit || model.sentTextWasEdited || model.textDelivery != .ready {
                Text(composerStatus)
                    .foregroundStyle(model.textDelivery == .uncertain ? Color.orange : Palette.muted)
                    .accessibilityIdentifier("textDeliveryStatus")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.muted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 2)
    }

    private var composerActions: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            if model.liveTextPaused {
                composerIcon("arrow.clockwise", label: String(localized: "检查电脑后重新读取输入框"), identifier: "resumeLiveText") {
                    model.restartLiveTextEditing()
                }
            } else if !model.usesLiveText && (model.textDelivery == .uncertain || model.textDelivery == .sent || model.sentTextWasEdited) {
                composerIcon("arrow.clockwise", label: String(localized: "检查电脑后允许重发"), identifier: "allowTextResend") {
                    interruptTouch(); resendAlert = true
                }
                .disabled(model.sendingText || speechBusy)
            }
            composerIcon("trash", label: String(localized: "清空草稿"), identifier: "clearTextDraft") {
                interruptTouch(); clearAlert = true
            }
            .disabled(model.draft.isEmpty || model.composing || model.sendingText || speechBusy || (model.usesLiveText && !model.liveTextReady))
            composerIcon("arrow.down", label: String(localized: "收起键盘"), identifier: "hideKeyboard") {
                keyboardFocused = false
                cancelSpeech()
            }
            .disabled(!keyboardFocused && !speechBusy)
            Button(action: sendCurrentDraft) {
                Group {
                    if model.sendingText { ProgressView().tint(Palette.background) }
                    else { Image(systemName: model.liveTextReady ? "checkmark" : "arrow.up").font(.system(size: 19, weight: .semibold)) }
                }
                .frame(width: 48, height: 44)
                .foregroundStyle(Palette.background)
                .background(Palette.mint, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canAttemptSend)
            .opacity(canAttemptSend || model.sendingText ? 1 : 0.45)
            .accessibilityLabel(model.usesLiveText ? String(localized: "实时同步") : String(localized: "发送"))
            .accessibilityIdentifier("sendText")
        }
        .frame(minHeight: 44)
    }

    private func composerIcon(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(Palette.muted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var canAttemptSend: Bool {
        // Keep the control stable, including after an ACK. A native keyboard can
        // update its text storage before publishing the binding; flush it first.
        !model.usesLiveText && inputEnabled && !model.sendingText && !speechBusy && model.textDelivery != .uncertain
    }

    private var fallbackInputNotice: String {
        if !model.controlAvailable { return String(localized: "未连接电脑，草稿会保留在手机上。") }
        if !model.receiverState.supportsLiveText { return String(localized: "当前设备不支持实时输入，请确认后发送。") }
        if model.liveTextStatus == .unsupported { return String(localized: "当前输入框不支持实时输入，请确认后发送。") }
        return String(localized: "草稿尚未实时同步，请确认后发送。")
    }

    private func sendCurrentDraft() {
        guard canAttemptSend, draftEditorControl.flushForSend() else { return }
        model.sendText()
    }

    private var composerStatus: String {
        if dictation.isRecording { return model.usesLiveText ? String(localized: "正在听写并实时同步…") : String(localized: "正在听写，结束后确认文字再发送。") }
        if dictation.state == .finishing { return String(localized: "正在整理听写结果…") }
        if model.remoteTextFocus == .protected { return String(localized: "电脑当前为安全输入框，不会自动听写。") }
        if model.demo && model.textDelivery == .sent { return String(localized: "演示反馈：文字没有发送到电脑。") }
        return model.textStatus
    }

    private func toggleKeyboard() {
        guard !televisionSelected else { return }
        interruptTouch()
        cancelSpeech()
        if keyboardFocused { keyboardFocused = false; composerVisible = false }
        else {
            composerVisible = true
            keyboardFocused = true
            model.openTextEditor()
        }
    }
    private func toggleDictation() {
        guard !televisionSelected, model.controlAvailable, !model.sendingText, !model.composing, model.remoteTextFocus != .protected else { return }
        let releasedDrag = model.dragging
        interruptTouch()
        if dictation.isRecording {
            // Recording suppresses haptics. Stop capture and release its audio
            // session before acknowledging the explicit stop tap.
            dictation.stop()
            dictationImpact.impactOccurred()
            return
        }
        if speechBusy || speechRequest != nil {
            cancelSpeech()
            if !releasedDrag { dictationImpact.impactOccurred() }
            return
        }
        // A drag release already supplies feedback. This confirms the tap,
        // not microphone authorization or a successful recording start.
        if !releasedDrag { dictationImpact.impactOccurred() }
        keyboardFocused = false
        composerVisible = true
        let request = UUID(); speechRequest = request
        model.openTextEditor {
            guard !televisionSelected, speechRequest == request, model.controlAvailable, scenePhase == .active else { return }
            speechBaseDraft = model.draft
            speechBaseSnapshot = model.liveTextReady ? LiveTextSnapshot(text: model.draft, selection: model.draftSelection) : nil
            speechOwnsDraft = true
            dictationStartTask?.cancel()
            dictationStartTask = Task {
                guard !Task.isCancelled, !televisionSelected, speechRequest == request, model.controlAvailable, scenePhase == .active else { return }
                await dictation.start()
            }
        }
    }
    private func applyRemoteFocus() {
        guard !televisionSelected, model.canControl, scenePhase == .active, !pairingSheet, !statusSheet, !showingSpeechError,
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
        edgeScrollControl.cancel()
        touchControl.cancel()
        model.pauseInput()
        tv.pauseInput()
        androidTV.pauseInput()
    }
    private func selectTelevision() {
        stopInteraction()
        androidTV.disconnect()
        androidSelected = false
        composerVisible = false
        model.setDesktopControlEnabled(false)
        tv.disconnect()
    }
    private func selectAndroidTelevision() {
        stopInteraction()
        composerVisible = false
        tv.disconnect()
        androidTV.disconnect()
        androidSelected = true
        model.setDesktopControlEnabled(false, televisionTarget: "androidtv")
    }
    private func selectComputer() {
        stopInteraction()
        tv.disconnect()
        androidTV.disconnect()
        androidSelected = false
        composerVisible = false
        handledFocusRevision = nil
        model.setDesktopControlEnabled(true)
    }
    private func resumeCurrentInput() {
        if androidTVSelected { androidTV.resumeInput() }
        else if televisionSelected { tv.resumeInput() }
        else { applyRemoteFocus() }
    }
    private func scrollCurrentDevice(_ delta: Double) {
        if androidTVSelected { androidTV.scroll(dy: delta) }
        else if televisionSelected { tv.scroll(dy: delta) }
        else { model.scroll(dy: delta) }
    }
}

private struct MicrophoneButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prepareFeedback: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isEnabled && configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.90 : 1)
            .brightness(pressed ? -0.12 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: pressed ? 0.10 : 0.16), value: pressed)
            // Keep the full target while its visible surface compresses.
            .frame(width: 64, height: 64)
            .contentShape(Circle())
            .onChange(of: pressed) { _, down in
                if down { prepareFeedback() }
            }
    }
}

#Preview { RemoteView(model: ControllerModel(demo: true)).preferredColorScheme(.dark) }
