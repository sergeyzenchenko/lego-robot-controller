import AVFoundation
import UIKit

enum CameraCapture {
    /// Captures a single JPEG photo from the front camera.
    /// Returns compressed JPEG data (quality 0.5, max 512px).
    static func capturePhoto() async throws -> Data {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        // Prefer telephoto for more natural perspective (wide-angle distorts distances)
        let device: AVCaptureDevice
        if let telephoto = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
            device = telephoto
        } else if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            device = wide
        } else {
            throw CaptureError.noCamera
        }
        AppLog.debug("[Camera] Using: \(device.localizedName)")

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.noCamera }
        session.addInput(input)

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else { throw CaptureError.noCamera }
        session.addOutput(output)

        session.startRunning()
        // Give the camera a moment to warm up (auto-exposure/focus)
        try await Task.sleep(for: .milliseconds(500))

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let delegate = PhotoDelegate(continuation: continuation)
            // Keep delegate alive until callback
            objc_setAssociatedObject(output, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            let settings = AVCapturePhotoSettings()
            output.capturePhoto(with: settings, delegate: delegate)
        }

        session.stopRunning()

        // Resize + compress
        guard let image = UIImage(data: data) else { throw CaptureError.noImage }
        let resized = resize(image, maxDimension: 512)
        guard let jpeg = resized.jpegData(compressionQuality: 0.5) else { throw CaptureError.noImage }

        AppLog.debug("[Camera] Captured \(jpeg.count) bytes")
        return jpeg
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        if scale >= 1.0 { return image }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var continuation: CheckedContinuation<Data, Error>?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: CaptureError.noImage)
        }
        continuation = nil
    }
}

enum CaptureError: LocalizedError {
    case noCamera
    case noImage

    var errorDescription: String? {
        switch self {
        case .noCamera: "No front camera available"
        case .noImage: "Failed to capture image"
        }
    }
}
