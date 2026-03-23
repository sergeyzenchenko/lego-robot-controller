import SwiftUI
import ARKit

struct DepthDebugSnapshot {
    let heatmapImage: CGImage
    let payload: AgentDepthPayload
    let trackingState: String
    let isTracking: Bool
    let fps: Int
}

@MainActor
final class DepthDebugViewModel: ObservableObject {
    @Published var snapshot: DepthDebugSnapshot?

    private var session: ARSession?
    private var delegate: DepthDelegate?
    private var updateTask: Task<Void, Never>?

    func start() {
        let session = ARSession()
        let delegate = DepthDelegate()
        session.delegate = delegate
        self.session = session
        self.delegate = delegate

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        config.planeDetection = []
        config.environmentTexturing = .none
        session.run(config)

        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.updateSnapshot()
            }
        }
    }

    func stop() {
        updateTask?.cancel()
        session?.pause()
        session = nil
        delegate = nil
    }

    private func updateSnapshot() {
        guard let delegate, let frame = delegate.latestFrame else { return }
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }

        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap!

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        }

        let displayBuffer = RotatedDepthBuffer(
            depths: CVPixelBufferGetBaseAddress(depthMap)!.assumingMemoryBound(to: Float32.self),
            confs: CVPixelBufferGetBaseAddress(confidenceMap)!.assumingMemoryBound(to: UInt8.self),
            rawW: CVPixelBufferGetWidth(depthMap),
            rawH: CVPixelBufferGetHeight(depthMap)
        )

        let heatmapImage = renderHeatmapImage(
            buf: displayBuffer,
            w: displayBuffer.width,
            h: displayBuffer.height
        )

        if let rawDepth = frame.sceneDepth {
            let rawMap = rawDepth.depthMap
            let rawConfidenceMap = rawDepth.confidenceMap!
            CVPixelBufferLockBaseAddress(rawMap, .readOnly)
            CVPixelBufferLockBaseAddress(rawConfidenceMap, .readOnly)

            let analysisBuffer = RotatedDepthBuffer(
                depths: CVPixelBufferGetBaseAddress(rawMap)!.assumingMemoryBound(to: Float32.self),
                confs: CVPixelBufferGetBaseAddress(rawConfidenceMap)!.assumingMemoryBound(to: UInt8.self),
                rawW: CVPixelBufferGetWidth(rawMap),
                rawH: CVPixelBufferGetHeight(rawMap)
            )
            let payload = analyzeDepth(buf: analysisBuffer)

            CVPixelBufferUnlockBaseAddress(rawMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(rawConfidenceMap, .readOnly)

            buildSnapshot(heatmapImage: heatmapImage, payload: payload, frame: frame)
        } else {
            let payload = analyzeDepth(buf: displayBuffer)
            buildSnapshot(heatmapImage: heatmapImage, payload: payload, frame: frame)
        }
    }

    private func buildSnapshot(heatmapImage: CGImage?, payload: AgentDepthPayload, frame: ARFrame) {
        guard let heatmapImage else { return }

        let trackingSummary = summarizeTrackingState(frame.camera.trackingState)
        snapshot = DepthDebugSnapshot(
            heatmapImage: heatmapImage,
            payload: payload,
            trackingState: trackingSummary.label,
            isTracking: trackingSummary.isTracking,
            fps: delegate?.fps ?? 0
        )
    }

    private func summarizeTrackingState(_ trackingState: ARCamera.TrackingState) -> (label: String, isTracking: Bool) {
        switch trackingState {
        case .normal:
            return ("Normal", true)
        case .limited(let reason):
            switch reason {
            case .initializing:
                return ("Initializing...", false)
            case .excessiveMotion:
                return ("Too much motion", false)
            case .insufficientFeatures:
                return ("Low features", false)
            case .relocalizing:
                return ("Relocalizing...", false)
            @unknown default:
                return ("Limited", false)
            }
        case .notAvailable:
            return ("Not available", false)
        }
    }

    private func renderHeatmapImage(buf: RotatedDepthBuffer, w: Int, h: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        for y in 0..<h {
            for x in 0..<w {
                let (distance, confidence) = buf.sample(x: x, y: y)
                let offset = (y * w + x) * 4
                let (r, g, b) = depthRGB(distance: distance, confidence: confidence)
                pixels[offset] = r
                pixels[offset + 1] = g
                pixels[offset + 2] = b
                pixels[offset + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }

    private func depthRGB(distance: Float32, confidence: UInt8) -> (UInt8, UInt8, UInt8) {
        guard distance > 0.1 && distance < 5.0 else { return (0, 0, 0) }

        let t = min(max((distance - 0.2) / 2.8, 0), 1)
        let alpha: Float = confidence >= 1 ? 1.0 : 0.4

        let r: Float
        let g: Float
        let b: Float

        if t < 0.25 {
            let s = t / 0.25
            r = 1.0
            g = s
            b = 0
        } else if t < 0.5 {
            let s = (t - 0.25) / 0.25
            r = 1.0 - s
            g = 1.0
            b = 0
        } else if t < 0.75 {
            let s = (t - 0.5) / 0.25
            r = 0
            g = 1.0
            b = s
        } else {
            let s = (t - 0.75) / 0.25
            r = 0
            g = 1.0 - s
            b = 1.0
        }

        return (
            UInt8(r * alpha * 255),
            UInt8(g * alpha * 255),
            UInt8(b * alpha * 255)
        )
    }

    private func analyzeDepth(buf: RotatedDepthBuffer) -> AgentDepthPayload {
        let width = buf.width
        let height = buf.height

        var grid: [[DepthCell]] = []
        for row in 0..<5 {
            var gridRow: [DepthCell] = []
            for column in 0..<5 {
                let sampleX = (width * (column * 2 + 1)) / 10
                let sampleY = (height * (row * 2 + 1)) / 10
                let (distance, confidence) = buf.sample(x: sampleX, y: sampleY)
                gridRow.append(
                    DepthCell(
                        distanceCM: distance > 0.2 ? Int(distance * 100) : nil,
                        confidence: confidence >= 2 ? "high" : confidence >= 1 ? "medium" : "low"
                    )
                )
            }
            grid.append(gridRow)
        }

        var nearestDistance: Float = .infinity
        var nearestX = width / 2
        let startRow = height * 2 / 5

        for y in startRow..<height {
            for x in 0..<width {
                let (distance, confidence) = buf.sample(x: x, y: y)
                if distance > 0.2 && distance < nearestDistance && confidence >= 1 {
                    nearestDistance = distance
                    nearestX = x
                }
            }
        }

        var centerLaneDistance: Float = .infinity
        let centerLeft = width / 3
        let centerRight = (width * 2) / 3

        for y in startRow..<height {
            for x in centerLeft..<centerRight {
                let (distance, confidence) = buf.sample(x: x, y: y)
                if distance > 0.2 && distance < centerLaneDistance && confidence >= 1 {
                    centerLaneDistance = distance
                }
            }
        }

        let direction = nearestX < width / 3 ? "left" : nearestX > (width * 2) / 3 ? "right" : "center"

        return AgentDepthPayload(
            grid5x5: grid,
            nearestObstacleCM: nearestDistance.isFinite ? Int(nearestDistance * 100) : 500,
            nearestObstacleDirection: direction,
            clearPathAheadCM: centerLaneDistance.isFinite ? Int(centerLaneDistance * 100) : 500,
            lidarAvailable: true
        )
    }
}

private final class DepthDelegate: NSObject, ARSessionDelegate {
    var latestFrame: ARFrame?
    var fps: Int = 0

    private var frameCount = 0
    private var lastFPSTime = Date()

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestFrame = frame
        frameCount += 1

        let now = Date()
        if now.timeIntervalSince(lastFPSTime) >= 1.0 {
            fps = frameCount
            frameCount = 0
            lastFPSTime = now
        }
    }
}
