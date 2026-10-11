import SwiftUI
import AVFoundation

struct PairingView: View {
    @ObservedObject var model: ControllerModel
    @Environment(\.dismiss) private var dismiss
    @State private var rawLink = ""
    @State private var showScanner = false
    @State private var forgetAlert = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    Image(systemName: "desktopcomputer.and.arrow.down")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(Palette.mint)
                        .padding(.top, 14)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("连接你的客厅电脑")
                            .font(.system(size: 27, weight: .semibold))
                        Text("在 Windows 或 Mac 上打开 Sofatap 接收器，扫描它显示的二维码。手机与电脑连接同一个家庭网络。")
                            .font(.system(size: 15)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { showScanner = true } label: {
                        Label("扫描电脑二维码", systemImage: "qrcode.viewfinder")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 58)
                            .foregroundStyle(Palette.background)
                            .background(Palette.mint, in: RoundedRectangle(cornerRadius: 19))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("或粘贴完整配对链接").font(.system(size: 14, weight: .medium))
                        TextField("sofatap://pair?host=…", text: $rawLink, axis: .vertical)
                            .font(.system(size: 13, design: .monospaced))
                            .lineLimit(3...6)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .privacySensitive()
                            .padding(15)
                            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("pairingLink")
                        Button("安全保存并连接") {
                            model.acceptPairing(rawLink)
                            if model.pairingError == nil { rawLink = ""; dismiss() }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .disabled(rawLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let error = model.pairingError {
                            Text(error).font(.footnote).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let pairing = model.pairing, !model.demo {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("已配对的电脑", systemImage: "checkmark.shield")
                                .font(.system(size: 14, weight: .medium))
                            Text("\(pairing.host):\(pairing.port)")
                                .font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.muted)
                            Button("移除配对", role: .destructive) { forgetAlert = true }
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 17))
                    }
                    Label("配对密钥只保存在 iPhone 钥匙串中。请勿分享二维码或配对链接。", systemImage: "lock.shield")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            .background(Palette.background)
            .navigationTitle("配对电脑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showScanner) {
                ScannerSheet { value in
                    model.acceptPairing(value)
                    if model.pairingError == nil { showScanner = false; dismiss() }
                }
            }
            .alert("移除电脑配对？", isPresented: $forgetAlert) {
                Button("取消", role: .cancel) {}
                Button("移除", role: .destructive) { model.forgetPairing() }
            } message: { Text("下次连接需要重新扫描电脑上的二维码。手机文字草稿会保留。") }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                QRScanner(onScan: onScan, onError: { error = $0 })
                VStack {
                    Text("将 电脑配对二维码放入画面")
                        .font(.system(size: 15, weight: .medium))
                        .padding(14).background(.black.opacity(0.65), in: Capsule())
                    Spacer()
                    if let error {
                        Text(error).font(.system(size: 15)).multilineTextAlignment(.center)
                            .padding(20).background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
                        Button("返回粘贴配对链接") { dismiss() }
                            .padding(15).tint(Palette.mint)
                    }
                }.padding(24)
            }
            .navigationTitle("扫描二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(onScan: onScan, onError: onError)
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let capture = AVCaptureSession()
    private let cameraQueue = DispatchQueue(label: "com.chekusu.sofatap.camera")
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private var preview: AVCaptureVideoPreviewLayer?
    private var scanned = false
    private var stopped = false
    init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onScan = onScan; self.onError = onError
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
                    else { self.onError("相机权限未开启。可在设置中开启，或粘贴电脑上的完整配对链接。") }
                }
            }
        default: onError("相机权限未开启。可在设置中开启，或粘贴电脑上的完整配对链接。")
        }
    }
    private func configure() {
        guard !stopped else { return }
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera) else {
            onError("这台设备没有可用相机。请返回并粘贴电脑上的完整配对链接。")
            return
        }
        let output = AVCaptureMetadataOutput()
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
            onError("无法打开相机，请尝试粘贴配对链接。")
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
        guard (try? Pairing.parse(value)) != nil else { onError("这不是有效的 Sofatap 配对二维码。请扫描电脑接收器显示的二维码。"); return }
        scanned = true
        stop()
        onScan(value)
    }
    func stop() {
        stopped = true
        cameraQueue.async { [capture] in if capture.isRunning { capture.stopRunning() } }
    }
}
