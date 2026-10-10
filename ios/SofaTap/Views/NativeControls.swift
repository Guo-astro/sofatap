import SwiftUI
import UIKit

struct NativeDraftEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var composing: Bool
    var disabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = UIColor(white: 0.94, alpha: 1)
        view.tintColor = UIColor(red: 0.722, green: 0.953, blue: 0.816, alpha: 1)
        view.font = .systemFont(ofSize: 21, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
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
        context.coordinator.parent = self
        // Replacing text during an IME/voice composition would destroy the user's marked range.
        if view.markedTextRange == nil && view.text != text { view.text = text }
        view.isEditable = !disabled
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeDraftEditor
        weak var textView: UITextView?
        init(_ parent: NativeDraftEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.composing = textView.markedTextRange != nil
            parent.text = textView.text
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            let marked = textView.markedTextRange != nil
            if parent.composing != marked { parent.composing = marked }
        }
        @objc func done() { textView?.resignFirstResponder() }
    }
}

struct TouchSurface: UIViewRepresentable {
    let enabled: Bool
    let onMove: (Double, Double) -> Void
    let onTap: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.accessibilityLabel = "电脑触控板"
        view.accessibilityHint = "滑动移动电脑光标，轻点单击左键"
        view.accessibilityIdentifier = "touchpad"
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.require(toFail: pan)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        view.isUserInteractionEnabled = enabled
    }
    final class Coordinator: NSObject {
        var parent: TouchSurface
        init(_ parent: TouchSurface) { self.parent = parent }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard parent.enabled else { return }
            let delta = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            if gesture.state == .changed { parent.onMove(delta.x, delta.y) }
        }
        @objc func tap() { if parent.enabled { parent.onTap() } }
    }
}

struct HoldControl<Label: View>: View {
    let enabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var pressed = false
    var body: some View {
        label()
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !pressed else { return }
                    pressed = true
                    onPress()
                }
                .onEnded { _ in release() })
            .onChange(of: enabled) { _, value in if !value { release() } }
            .onDisappear { release() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "按住") { if enabled { onPress() } }
            .accessibilityAction(named: "松开") { onRelease() }
    }
    private func release() {
        guard pressed else { return }
        pressed = false
        onRelease()
    }
}
