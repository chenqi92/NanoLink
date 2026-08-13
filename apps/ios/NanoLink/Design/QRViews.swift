import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins
import UIKit

enum QRScannerFailure {
    case permissionDenied
    case unavailable
}

/// Native AVFoundation metadata scanner used by the add-server QR flow.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (QRScannerFailure) -> Void
    @Binding var torchOn: Bool

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode
        controller.onError = onError
        controller.requestAndStart()
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {
        controller.onCode = onCode
        controller.onError = onError
        controller.setTorch(torchOn)
    }

    static func dismantleUIViewController(_ controller: QRScannerController, coordinator: ()) {
        controller.stop()
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((QRScannerFailure) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var hasDelivered = false
    private var requestedTorch = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configure() }
                    else { self?.onError?(.permissionDenied) }
                }
            }
        default:
            onError?(.permissionDenied)
        }
    }

    private func configure() {
        guard session.inputs.isEmpty else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onError?(.unavailable)
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onError?(.unavailable)
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        preview = layer
        let requestedTorch = self.requestedTorch
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
            DispatchQueue.main.async { [weak self] in self?.applyTorch(requestedTorch) }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasDelivered,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        hasDelivered = true
        session.stopRunning()
        onCode?(value)
    }

    func setTorch(_ on: Bool) {
        requestedTorch = on
        guard session.isRunning else { return }
        applyTorch(on)
    }

    private func applyTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on { try device.setTorchModeOn(level: 1) }
            else { device.torchMode = .off }
            device.unlockForConfiguration()
        } catch { }
    }

    func stop() {
        requestedTorch = false
        applyTorch(false)
        if session.isRunning { session.stopRunning() }
    }
}

/// Core Image QR renderer. No external package is required.
struct QRCodeView: View {
    let value: String
    var size: CGFloat = 220

    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.black)
            }
        }
        .frame(width: size, height: size)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
