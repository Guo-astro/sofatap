import SwiftUI

/// Cleanup for the retired account-password experiment. This view never reads
/// a secret, starts Face ID, enrolls a credential, or contacts the computer.
struct LegacyUnlockCredentialRemovalView: View {
    @ObservedObject var unlock: ComputerUnlockController
    @State private var removeAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "旧版解锁记录")).font(.headline)
            Text(String(localized: "账户密码解锁实验已停用。可以从这台 iPhone 删除旧版保存的记录。"))
                .font(.footnote).foregroundStyle(Palette.muted)
            Button(String(localized: "删除旧版解锁记录"), role: .destructive) { removeAlert = true }
                .accessibilityIdentifier("removeLegacyUnlockCredential")
            if case .failed(let message) = unlock.state {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
        }
        .alert(String(localized: "删除旧版解锁记录？"), isPresented: $removeAlert) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "删除"), role: .destructive, action: unlock.removePassword)
        } message: {
            Text(String(localized: "仅删除这台 iPhone 保存的旧版密码和登录服务授权，不会读取密码或更改 Windows 账户。"))
        }
    }
}
