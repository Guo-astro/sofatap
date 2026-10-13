import SwiftUI
import AVFoundation

struct PairingView: View {
    @ObservedObject var model: ControllerModel
    @ObservedObject var tv: WebOSTVController
    @ObservedObject var androidTV: AndroidTVController
    let selectAndroidTV: () -> Void
    let selectTV: () -> Void
    let selectComputer: () -> Void
    let androidSelected: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var renameTarget: DeviceTarget?
    @State private var removeTarget: DeviceTarget?
    @State private var editedName = ""

    private struct DeviceTarget: Identifiable {
        enum Kind { case computer, android, webos }
        let id: UUID
        let kind: Kind
        let name: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    savedDevices
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "添加设备")).font(.headline)
                        NavigationLink {
                            ComputerPairingView(model: model, selectComputer: selectComputer, finishPairing: { dismiss() })
                        } label: { addLabel(String(localized: "电脑"), symbol: "desktopcomputer", detail: "Windows · Mac · Linux") }
                        NavigationLink {
                            AndroidTVPairingView(tv: androidTV, selectTV: selectAndroidTV, finishPairing: { dismiss() })
                        } label: { addLabel("Android TV / Google TV", symbol: "tv", detail: String(localized: "实验版")) }
                        NavigationLink {
                            TVPairingView(tv: tv, selectTV: selectTV, finishPairing: { dismiss() })
                        } label: { addLabel("LG webOS", symbol: "tv", detail: String(localized: "预览")) }
                    }
                    if let error = model.pairingError { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if let error = androidTV.managementError { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if let error = tv.managementError { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if !model.desktopControlEnabled && androidSelected &&
                        (androidTV.phase == .failed || (androidTV.phase == .ready && androidTV.status?.available != true)) {
                        Text(androidTV.notice).font(.footnote).foregroundStyle(.orange)
                    }
                    if !model.desktopControlEnabled && !androidSelected && tv.phase == .failed {
                        Text(tv.notice).font(.footnote).foregroundStyle(.orange)
                    }
                    if model.desktopControlEnabled && model.pairing != nil &&
                        (!model.connected || !model.inputAvailable) && model.pairingError == nil {
                        Text(model.notice).font(.footnote).foregroundStyle(Palette.muted)
                    }
                    if model.unlock.savedBinding != nil { LegacyUnlockCredentialRemovalView(unlock: model.unlock) }
                    Text(String(localized: "一次只控制当前选择的设备。切换设备不会自动发送手机草稿。"))
                        .font(.footnote).foregroundStyle(Palette.muted)
                }.padding(20)
            }
            .background(Palette.background)
            .navigationTitle(String(localized: "我的设备"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "完成")) { dismiss() } } }
            .alert(String(localized: "重命名设备"), isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField(String(localized: "设备名称"), text: $editedName)
                Button(String(localized: "取消"), role: .cancel) { renameTarget = nil }
                Button(String(localized: "保存")) { saveName() }
            } message: { Text(String(localized: "名称只在这台 iPhone 上更改。")) }
            .alert(String(localized: "移除此设备？"), isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } })) {
                Button(String(localized: "取消"), role: .cancel) { removeTarget = nil }
                Button(String(localized: "移除"), role: .destructive) { removeDevice() }
            } message: { Text(String(localized: "仅从这台 iPhone 移除，不会关闭接收器或影响其他手机。再次连接需要重新配对。")) }
        }
        .tint(Palette.mint).preferredColorScheme(.dark)
    }

    @ViewBuilder private var savedDevices: some View {
        if model.savedDevices.isEmpty && androidTV.savedDevices.isEmpty && tv.savedDevices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 28)).foregroundStyle(Palette.mint)
                Text(String(localized: "还没有配对设备")).font(.headline)
                Text(String(localized: "添加电脑或电视，之后可在这里快速切换。"))
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }.padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "已保存的设备")).font(.headline)
                ForEach(model.savedDevices) { device in
                    deviceRow(id: device.id, name: device.displayName,
                              detail: computerPlatform(device.platform) + " · " + device.credential.host,
                              symbol: device.platform == "macos" ? "laptopcomputer" : "desktopcomputer",
                              kind: .computer, selected: model.desktopControlEnabled && model.selectedDeviceID == device.id,
                              connected: model.connected, busy: model.connecting) {
                        selectComputer()
                        model.selectDevice(device.id)
                        if model.pairingError == nil && model.selectedDeviceID == device.id { dismiss() }
                    }
                }
                ForEach(androidTV.savedDevices) { device in
                    deviceRow(id: device.id, name: device.displayName, detail: "Android TV · " + device.credential.host,
                              symbol: "tv", kind: .android,
                              selected: !model.desktopControlEnabled && androidSelected && androidTV.selectedDeviceID == device.id,
                              connected: androidTV.phase == .ready, busy: androidTV.busy) {
                        selectAndroidTV()
                        androidTV.selectDevice(device.id)
                        if androidTV.managementError == nil && androidTV.selectedDeviceID == device.id { dismiss() }
                    }
                }
                ForEach(tv.savedDevices) { device in
                    deviceRow(id: device.id, name: device.displayName, detail: "LG webOS · " + device.credential.host,
                              symbol: "tv", kind: .webos,
                              selected: !model.desktopControlEnabled && !androidSelected && tv.selectedDeviceID == device.id,
                              connected: tv.phase == .ready, busy: tv.busy) {
                        selectTV()
                        tv.selectDevice(device.id)
                        if tv.managementError == nil && tv.selectedDeviceID == device.id { dismiss() }
                    }
                }
            }
        }
    }

    private func deviceRow(id: UUID, name: String, detail: String, symbol: String, kind: DeviceTarget.Kind,
                           selected: Bool, connected: Bool, busy: Bool, select: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                select()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 23)).frame(width: 32)
                        .foregroundStyle(selected ? Palette.mint : Palette.muted)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                        if selected {
                            Label(busy ? String(localized: "正在安全连接…") : connected ? String(localized: "当前设备 · 已连接") : String(localized: "当前设备 · 未连接"),
                                  systemImage: connected ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(connected ? Palette.mint : Palette.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 14).padding(.leading, 14).contentShape(Rectangle())
            }.buttonStyle(RemoteIconButtonStyle())
            Menu {
                Button { editedName = name; renameTarget = DeviceTarget(id: id, kind: kind, name: name) } label: {
                    Label(String(localized: "重命名设备"), systemImage: "pencil")
                }
                if selected && (connected || busy) {
                    Button {
                        switch kind {
                        case .computer: model.disconnectDevice()
                        case .android: androidTV.disconnect()
                        case .webos: tv.disconnect()
                        }
                    } label: { Label(String(localized: "断开连接"), systemImage: "pause.circle") }
                }
                Button(role: .destructive) { removeTarget = DeviceTarget(id: id, kind: kind, name: name) } label: {
                    Label(String(localized: "移除配对"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 44, height: 52).contentShape(Rectangle())
            }.accessibilityLabel(String(localized: "管理设备") + ", " + name)
        }
        .background(selected ? Palette.mint.opacity(0.075) : Palette.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Palette.mint.opacity(0.36) : .clear, lineWidth: 1))
    }

    private func computerPlatform(_ value: String?) -> String {
        switch value { case "macos": return "Mac"; case "windows": return "Windows"; case "linux": return "Linux"; default: return String(localized: "电脑") }
    }
    private func addLabel(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28)
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer(minLength: 4)
            Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Image(systemName: "chevron.forward").font(.system(size: 10, weight: .semibold))
        }.padding(14).foregroundStyle(Palette.mint)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 15))
    }
    private func saveName() {
        guard let target = renameTarget else { return }
        switch target.kind {
        case .computer: model.renameDevice(target.id, name: editedName)
        case .android: androidTV.renameDevice(target.id, name: editedName)
        case .webos: tv.renameDevice(target.id, name: editedName)
        }
        renameTarget = nil
    }
    private func removeDevice() {
        guard let target = removeTarget else { return }
        switch target.kind {
        case .computer: model.removeDevice(target.id)
        case .android: androidTV.removeDevice(target.id)
        case .webos: tv.removeDevice(target.id)
        }
        removeTarget = nil
    }
}

private struct ComputerPairingView: View {
    @ObservedObject var model: ControllerModel
    let selectComputer: () -> Void
    let finishPairing: () -> Void
    @State private var rawLink = ""
    @State private var showScanner = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(String(localized: "连接你的客厅电脑"), systemImage: "desktopcomputer")
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.mint)
                Text(String(localized: "在电脑上打开 Sofatap 接收器，扫描它显示的二维码。手机与电脑连接同一个家庭网络。"))
                    .foregroundStyle(Palette.muted)
                Link(String(localized: "下载电脑接收器"), destination: URL(string: "https://github.com/chekusu/sofatap/releases")!)
                Button { showScanner = true } label: {
                    Label(String(localized: "扫描电脑二维码"), systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.borderedProminent)
                Text(String(localized: "或粘贴完整配对链接")).font(.subheadline)
                TextField("sofatap://pair?host=…", text: $rawLink, axis: .vertical)
                    .font(.caption.monospaced()).lineLimit(3...6)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    .padding(15).background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("pairingLink")
                Button(String(localized: "安全保存并连接")) { accept(rawLink) }
                    .disabled(rawLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error = model.pairingError { Text(error).font(.footnote).foregroundStyle(.orange) }
                Label(String(localized: "配对密钥只保存在 iPhone 钥匙串中。请勿分享二维码或配对链接。"), systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }.padding(20)
        }
        .background(Palette.background).navigationTitle(String(localized: "连接设备"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScanner) { ScannerSheet { value in accept(value) } }
    }
    private func accept(_ raw: String) {
        guard (try? Pairing.parse(raw)) != nil else { model.acceptPairing(raw); return }
        selectComputer()
        model.acceptPairing(raw)
        if model.pairingError == nil { rawLink = ""; showScanner = false; finishPairing() }
    }
}

struct ScannerSheet: View {
    var accepts: (String) -> Bool = { (try? Pairing.parse($0)) != nil }
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                QRScanner(accepts: accepts, onScan: onScan, onError: { error = $0 })
                VStack {
                    Text(String(localized: "将 Sofatap 配对二维码放入画面"))
                        .font(.system(size: 15, weight: .medium))
                        .padding(14).background(.black.opacity(0.65), in: Capsule())
                    Spacer()
                    if let error {
                        Text(error).font(.system(size: 15)).multilineTextAlignment(.center)
                            .padding(20).background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
                        Button(String(localized: "返回粘贴配对链接")) { dismiss() }
                            .padding(15).tint(Palette.mint)
                    }
                }.padding(24)
            }
            .navigationTitle(String(localized: "扫描二维码"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "取消")) { dismiss() } } }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let accepts: (String) -> Bool
    let onScan: (String) -> Void
    let onError: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(accepts: accepts, onScan: onScan, onError: onError)
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let capture = AVCaptureSession()
    private let cameraQueue = DispatchQueue(label: "com.chekusu.sofatap.camera")
    private let accepts: (String) -> Bool
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private var preview: AVCaptureVideoPreviewLayer?
    private var scanned = false
    private var stopped = false
    init(accepts: @escaping (String) -> Bool, onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.accepts = accepts; self.onScan = onScan; self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.configure() }
                    else { self.onError(String(localized: "相机权限未开启。可在设置中开启，或粘贴接收器中的完整配对链接。")) }
                }
            }
        default: onError(String(localized: "相机权限未开启。可在设置中开启，或粘贴接收器中的完整配对链接。"))
        }
    }
    private func configure() {
        guard !stopped else { return }
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera) else {
            onError(String(localized: "这台设备没有可用相机。请返回并粘贴接收器中的完整配对链接。"))
            return
        }
        let output = AVCaptureMetadataOutput()
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
            onError(String(localized: "无法打开相机，请尝试粘贴配对链接。"))
            return
        }
        capture.addInput(input)
        capture.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: capture)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        cameraQueue.async { [capture] in capture.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !scanned, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        // Invalid or unrelated QRs stay in the scanner with actionable feedback.
        guard accepts(value) else { onError(String(localized: "这不是此设备类型的有效 Sofatap 配对二维码。请扫描接收器显示的二维码。")); return }
        scanned = true
        stop()
        onScan(value)
    }
    func stop() {
        stopped = true
        cameraQueue.async { [capture] in if capture.isRunning { capture.stopRunning() } }
    }
}
