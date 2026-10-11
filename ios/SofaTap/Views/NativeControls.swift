import SwiftUI
import UIKit

struct NativeDraftEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var composing: Bool
    @Binding var isFocused: Bool
    var disabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = UIColor(white: 0.94, alpha: 1)
        view.tintColor = UIColor(red: 0.722, green: 0.953, blue: 0.816, alpha: 1)
        view.font = .systemFont(ofSize: 19, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 12, left: 9, bottom: 12, right: 9)
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .default
        view.smartQuotesType = .default
        view.accessibilityLabel = "要发送到电脑的文字草稿"
        view.accessibilityIdentifier = "textDraft"
        let toolbar = UIToolbar()
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace),
                         UIBarButtonItem(title: "收起键盘", style: .done, target: context.coordinator, action: #selector(Coordinator.done))]
        toolbar.sizeToFit()
        view.inputAccessoryView = toolbar
        context.coordinator.textView = view
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // Replacing text during an IME/keyboard dictation composition would destroy
        // the marked range. Also preserve selection on unrelated SwiftUI updates.
        if view.markedTextRange == nil && view.text != text {
            let selection = view.selectedRange
            view.text = text
            let count = (text as NSString).length
            view.selectedRange = NSRange(location: min(selection.location, count),
                                         length: min(selection.length, max(0, count - selection.location)))
        }
        view.isEditable = !disabled
        // Focus changes after this representable update avoid mutating SwiftUI state
        // from UITextViewDelegate synchronously during a rendering pass.
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator, coordinator.textView === view else { return }
            if coordinator.parent.isFocused && !coordinator.parent.disabled {
                if !view.isFirstResponder && view.window != nil { view.becomeFirstResponder() }
            } else if view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        view.resignFirstResponder()
        view.delegate = nil
        coordinator.textView = nil
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeDraftEditor
        weak var textView: UITextView?
        init(_ parent: NativeDraftEditor) { self.parent = parent }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.isFocused = true }
        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
            parent.composing = false
            parent.text = textView.text
        }
        func textViewDidChange(_ textView: UITextView) {
            parent.composing = textView.markedTextRange != nil
            parent.text = textView.text
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            let marked = textView.markedTextRange != nil
            if parent.composing != marked { parent.composing = marked }
        }
        @objc func done() {
            parent.isFocused = false
            textView?.resignFirstResponder()
        }
    }
}

struct TouchSurface: UIViewRepresentable {
    let enabled: Bool
    let onMove: (Double, Double) -> Void
    let onLeftTap: () -> Void
    let onRightTap: () -> Void
    let onDraggingChanged: (Bool) -> Void
    let onScroll: (Double) -> Void

    func makeUIView(context: Context) -> TouchInputView {
        let view = TouchInputView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.isAccessibilityElement = true
        view.accessibilityLabel = "电脑触控板"
        view.accessibilityHint = "滑动移动光标；轻点左键；连续轻点两下右键；按住零点三秒拖动；双指滑动滚动"
        view.accessibilityIdentifier = "touchpad"
        view.configure(self)
        return view
    }
    func updateUIView(_ view: TouchInputView, context: Context) { view.configure(self) }
    static func dismantleUIView(_ view: TouchInputView, coordinator: ()) { view.cancelInput() }

    final class TouchInputView: UIView {
        private var parent: TouchSurface?
        private var state = TouchGestureState()
        private var contacts: [ObjectIdentifier: CGPoint] = [:]
        private var deadlineTimer: Timer?
        private var active = true

        override init(frame: CGRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(self, selector: #selector(inactive), name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
            accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "左键单击", target: self, selector: #selector(accessibleLeftClick)),
                UIAccessibilityCustomAction(name: "右键单击", target: self, selector: #selector(accessibleRightClick))
            ]
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { deadlineTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }

        func configure(_ parent: TouchSurface) {
            if !parent.enabled && self.parent?.enabled == true { cancelInput() }
            self.parent = parent
            isUserInteractionEnabled = parent.enabled && active
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { cancelInput() }
        }
        @objc private func inactive() {
            active = false
            cancelInput()
            isUserInteractionEnabled = false
        }
        @objc private func becameActive() {
            active = true
            isUserInteractionEnabled = parent?.enabled == true
        }
        func cancelInput() {
            deadlineTimer?.invalidate()
            deadlineTimer = nil
            contacts.removeAll()
            dispatch(state.cancel())
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard parent?.enabled == true, active else { return }
            for touch in touches { contacts[ObjectIdentifier(touch)] = touch.location(in: self) }
            dispatch(state.begin(at: centroid, count: contacts.count, time: event?.timestamp ?? now))
            scheduleDeadline()
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard parent?.enabled == true, active else { cancelInput(); return }
            for touch in touches where contacts[ObjectIdentifier(touch)] != nil {
                contacts[ObjectIdentifier(touch)] = touch.location(in: self)
            }
            dispatch(state.move(to: centroid, count: contacts.count, time: event?.timestamp ?? now))
            scheduleDeadline()
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard parent?.enabled == true, active else { cancelInput(); return }
            for touch in touches where contacts[ObjectIdentifier(touch)] != nil {
                contacts[ObjectIdentifier(touch)] = touch.location(in: self)
            }
            let finalPoint = centroid
            for touch in touches { contacts.removeValue(forKey: ObjectIdentifier(touch)) }
            dispatch(state.end(at: finalPoint, remainingCount: contacts.count, time: event?.timestamp ?? now))
            scheduleDeadline()
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelInput() }

        private var now: Double { ProcessInfo.processInfo.systemUptime }
        private var centroid: TouchGestureState.Point {
            guard !contacts.isEmpty else { return .init(x: 0, y: 0) }
            return .init(x: contacts.values.reduce(0) { $0 + $1.x } / Double(contacts.count),
                         y: contacts.values.reduce(0) { $0 + $1.y } / Double(contacts.count))
        }
        private func scheduleDeadline() {
            deadlineTimer?.invalidate()
            deadlineTimer = nil
            guard let deadline = state.nextDeadline, parent?.enabled == true, active else { return }
            let timer = Timer(timeInterval: max(0.001, deadline - now), repeats: false) { [weak self] _ in
                guard let self, self.parent?.enabled == true, self.active else { return }
                self.dispatch(self.state.advance(to: self.now))
                self.scheduleDeadline()
            }
            deadlineTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        private func dispatch(_ actions: [TouchGestureState.Action]) {
            guard let parent else { return }
            for action in actions {
                switch action {
                case .move(let dx, let dy): parent.onMove(dx, dy)
                case .leftClick: parent.onLeftTap()
                case .rightClick: parent.onRightTap()
                case .dragging(let down): parent.onDraggingChanged(down)
                case .scroll(let dy): parent.onScroll(dy)
                }
            }
        }
        @objc private func accessibleLeftClick() -> Bool {
            guard parent?.enabled == true, active else { return false }
            parent?.onLeftTap(); return true
        }
        @objc private func accessibleRightClick() -> Bool {
            guard parent?.enabled == true, active else { return false }
            parent?.onRightTap(); return true
        }
    }
}
