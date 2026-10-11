import SwiftUI
import UIKit

struct ComputerUnlockView: View {
    @ObservedObject var unlock: ComputerUnlockController
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var consent = false
    @State private var editing = false
    @State private var removeAlert = false
    @State private var retryAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Face ID 解锁电脑", systemImage: "faceid").font(.title2.weight(.semibold))
                Text("实验功能 · \(unlock.capability?.accountTypeLabel ?? "Windows 账户密码")").font(.caption).foregroundStyle(.orange)
                Text(unlock.explanation).foregroundStyle(Palette.muted)
                if let pairing = unlock.pairing {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(pairing.host, systemImage: "desktopcomputer")
                        if let capability = unlock.capability {
                            Label("Windows 用户：\(capability.accountName)", systemImage: "person.crop.circle")
                        }
                    }.font(.body.weight(.medium))
                }
                if unlock.supported {
                    if unlock.savedBinding != nil && !editing {
                        Label("计算机密码已保存在这台 iPhone", systemImage: "lock.shield")
                        Button(action: unlock.unlock) {
                            Label("用 Face ID 解锁", systemImage: "faceid")
                                .frame(maxWidth: .infinity).frame(height: 54)
                        }
                        .buttonStyle(.borderedProminent).disabled(!unlock.canUnlock)
                        Button("更换计算机密码") { editing = true; consent = false }
                            .disabled(unlock.state.busy)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(unlock.capability?.passwordLabel ?? "计算机账户密码").font(.headline)
                            SecureComputerPasswordField(password: $password, disabled: unlock.state.busy, label: unlock.capability?.passwordLabel ?? "计算机账户密码")
                                .frame(height: 48).padding(.horizontal, 12)
                                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                                .privacySensitive()
                                .accessibilityLabel(unlock.capability?.passwordLabel ?? "计算机账户密码")
                            Text(unlock.capability?.passwordHint ?? "请输入此账户的密码，不能使用 Windows Hello PIN。")
                                .font(.footnote).foregroundStyle(Palette.muted)
                            Toggle("将密码保存到这台 iPhone，并在每次发送前使用 Face ID", isOn: $consent)
                                .font(.subheadline).disabled(unlock.state.busy)
                            Button {
                                var bytes = Data(password.utf8)
                                password = ""
                                unlock.savePassword(bytes)
                                bytes.resetBytes(in: 0..<bytes.count)
                                consent = false; editing = false
                            } label: {
                                Label("通过 Face ID 安全保存", systemImage: "lock.shield")
                                    .frame(maxWidth: .infinity).frame(height: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!consent || password.isEmpty || !unlock.canEnroll)
                        }
                    }
                }
                if unlock.capability?.isMicrosoftAccount == true {
                    Text("如果 Windows 开启了‘仅允许 Windows Hello 登录 Microsoft 账户’，此密码方式不可用。Sofatap 不会替你修改此设置或账户的无密码状态。")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                if unlock.state.busy { ProgressView().tint(Palette.mint) }
                Text(unlock.state.message)
                    .font(.subheadline).foregroundStyle(unlock.state == .uncertain ? .orange : Palette.muted)
                if unlock.state.busy { Button("取消", action: unlock.cancel) }
                if unlock.state == .uncertain {
                    Button("我已查看电脑屏幕") { retryAlert = true }
                }
                if unlock.savedBinding != nil {
                    Button("移除此电脑的已存密码", role: .destructive) { removeAlert = true }
                        .disabled(unlock.state.busy)
                }
                Text("密码不会进入文字草稿、语音识别或聊天。重新录入 Face ID 后需重新保存密码。关闭电源、BitLocker 启动画面和 Windows Hello PIN 暂不支持。")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
            .padding(24)
        }
        .background(Palette.background)
        .navigationTitle("Face ID 解锁")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in if phase != .active { password = ""; consent = false } }
        .onDisappear { password = ""; consent = false; unlock.cancel() }
        .alert("移除此电脑的已存密码？", isPresented: $removeAlert) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) { unlock.removePassword(); password = ""; consent = false; editing = false }
        } message: { Text("会删除本机的密码和登录服务授权。电脑账户密码不会改变。") }
        .alert("允许开始新的解锁尝试？", isPresented: $retryAlert) {
            Button("取消", role: .cancel) {}
            Button("已确认", action: unlock.acknowledgeUnknownOutcome)
        } message: { Text("上一次可能已经解锁。确认后仍需手动点击 Face ID，不会自动重发密码。") }
    }
}

/// UIKit secure entry keeps this password out of the draft/voice path and blocks
/// copy/paste menus and autofill. It uses the system secure keyboard only.
private struct SecureComputerPasswordField: UIViewRepresentable {
    @Binding var password: String
    let disabled: Bool
    let label: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PasswordField {
        let field = PasswordField()
        field.isSecureTextEntry = true
        field.textContentType = nil
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.keyboardType = .default
        field.returnKeyType = .done
        field.placeholder = label
        field.textColor = .white
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }
    func updateUIView(_ field: PasswordField, context: Context) {
        context.coordinator.parent = self
        if field.text != password { field.text = password }
        field.isEnabled = !disabled
        if disabled { field.resignFirstResponder() }
    }
    static func dismantleUIView(_ field: PasswordField, coordinator: Coordinator) { field.text = ""; field.resignFirstResponder() }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SecureComputerPasswordField
        init(_ parent: SecureComputerPasswordField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.password = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard let text = field.text, let range = Range(range, in: text) else { return false }
            let changed = text.replacingCharacters(in: range, with: string)
            return changed.utf8.count <= 4096 && changed.utf16.count <= 1024 && !string.utf8.contains(0)
        }
    }
    final class PasswordField: UITextField {
        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
        override func paste(_ sender: Any?) {}
        override func copy(_ sender: Any?) {}
        override func cut(_ sender: Any?) {}
    }
}
