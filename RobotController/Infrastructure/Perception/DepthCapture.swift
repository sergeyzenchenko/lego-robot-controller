import ARKit
import UIKit

// MARK: - Depth Payload for Agent

struct AgentDepthPayload: Codable {
    let grid5x5: [[DepthCell]]
    let nearestObstacleCM: Int
    let nearestObstacleDirection: String
    let clearPathAheadCM: Int
    let lidarAvailable: Bool

    static let unavailable = AgentDepthPayload(
        grid5x5: [], nearestObstacleCM: 0, nearestObstacleDirection: "unknown",
        clearPathAheadCM: 0, lidarAvailable: false
    )

    var textDescription: String {
        guard lidarAvailable else { return "LiDAR unavailable." }

        var lines: [String] = []
        lines.append("Depth grid (5x5, cm, top=far bottom=near, left-to-right):")
        for row in grid5x5 {
            let cells = row.map { cell in
                if let d = cell.distanceCM {
                    return "\(d)\(cell.confidence == "low" ? "?" : "")"
                }
                return "-"
            }
            lines.append("  [\(cells.joined(separator: ", "))]")
        }
        lines.append("Nearest obstacle: \(nearestObstacleCM)cm (\(nearestObstacleDirection))")
        lines.append("Clear path ahead: \(clearPathAheadCM)cm")

        if nearestObstacleCM < 20 {
            lines.append("WARNING: Object within 20cm dead zone — LiDAR unreliable at this range.")
        } else if nearestObstacleCM < 30 {
            lines.append("CAUTION: Very close obstacle — do not drive forward.")
        }

        return lines.joined(separator: "\n")
    }
}

struct DepthCell: Codable {
    let distanceCM: Int?
    let confidence: String
}

// MARK: - Portrait-rotated depth access

/// The LiDAR depth buffer is always landscape (256×192).
/// When the phone is portrait, we rotate 90° CW so the depth aligns with the camera photo.
/// After rotation: portrait width = landscape height, portrait height = landscape width.
struct RotatedDepthBuffer {
    let depths: UnsafePointer<Float32>
    let confs: UnsafePointer<UInt8>
    let rawW: Int  // landscape width (256)
    let rawH: Int  // landscape height (192)

    /// Dimensions after rotation to portrait
    var width: Int { rawH }   // 192
    var height: Int { rawW }  // 256

    /// Sample at portrait-oriented coordinates (x: 0..<width, y: 0..<height)
    func sample(x: Int, y: Int) -> (Float32, UInt8) {
        // 90° CW rotation: portrait (px, py) in (rawH × rawW) → landscape (bufX, bufY) in (rawW × rawH)
        // bufX = py
        // bufY = (rawH - 1) - px
        let bufX = min(max(y, 0), rawW - 1)
        let bufY = min(max((rawH - 1) - x, 0), rawH - 1)
        let idx = bufY * rawW + bufX
        return (depths[idx], confs[idx])
    }
}

// MARK: - Depth Capture Manager

final class DepthCaptureManager: NSObject, @unchecked Sendable {
    static let shared = DepthCaptureManager()

    private var session: ARSession?
    private var latestFrame: ARFrame?
    private let lock = NSLock()

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    func start() {
        guard Self.isSupported else {
            AppLog.debug("[Depth] LiDAR not available on this device")
            return
        }

        let session = ARSession()
        session.delegate = self
        self.session = session

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth]
        config.planeDetection = []
        config.environmentTexturing = .none

        session.run(config)
        AppLog.debug("[Depth] ARSession started")
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        guard let session, Self.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth]
        config.planeDetection = []
        config.environmentTexturing = .none
        session.run(config, options: [])
    }

    func stop() {
        session?.pause()
        session = nil
        latestFrame = nil
    }

    func captureDepth() async -> AgentDepthPayload {
        guard Self.isSupported else { return .unavailable }

        if session == nil { start() }
        resume()

        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(33))
            let frame = lock.withLock { latestFrame }
            if let frame, frame.sceneDepth != nil {
                let result = analyzeDepth(frame: frame)
                pause()
                return result
            }
        }

        pause()
        return .unavailable
    }

    /// Get the raw frame for debug view (caller handles rotation)
    func getLatestFrame() -> ARFrame? {
        lock.withLock { latestFrame }
    }

    // MARK: - Analysis (portrait-rotated)

    private func analyzeDepth(frame: ARFrame) -> AgentDepthPayload {
        guard let depthData = frame.sceneDepth else { return .unavailable }

        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap!

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        }

        let buf = RotatedDepthBuffer(
            depths: CVPixelBufferGetBaseAddress(depthMap)!.assumingMemoryBound(to: Float32.self),
            confs: CVPixelBufferGetBaseAddress(confidenceMap)!.assumingMemoryBound(to: UInt8.self),
            rawW: CVPixelBufferGetWidth(depthMap),
            rawH: CVPixelBufferGetHeight(depthMap)
        )

        let w = buf.width   // portrait width
        let h = buf.height  // portrait height

        // 1. 5×5 grid in portrait orientation
        var grid: [[DepthCell]] = []
        for row in 0..<5 {
            var gridRow: [DepthCell] = []
            for col in 0..<5 {
                let cx = (w * (col * 2 + 1)) / 10
                let cy = (h * (row * 2 + 1)) / 10
                let (med, conf) = medianPatch(buf: buf, cx: cx, cy: cy)
                gridRow.append(DepthCell(
                    distanceCM: med > 0.2 ? Int(med * 100) : nil,
                    confidence: conf >= 2 ? "high" : conf >= 1 ? "medium" : "low"
                ))
            }
            grid.append(gridRow)
        }

        // 2. Nearest obstacle — bottom 60% of portrait image
        var minDist: Float = .infinity
        var minX = w / 2
        let startRow = h * 2 / 5
        for y in startRow..<h {
            for x in 0..<w {
                let (d, c) = buf.sample(x: x, y: y)
                if d > 0.2 && d < minDist && c >= 1 {
                    minDist = d
                    minX = x
                }
            }
        }

        // 3. Clear corridor — center third in portrait
        var corrMin: Float = .infinity
        let cl = w / 3
        let cr = (w * 2) / 3
        for y in startRow..<h {
            for x in cl..<cr {
                let (d, c) = buf.sample(x: x, y: y)
                if d > 0.2 && d < corrMin && c >= 1 { corrMin = d }
            }
        }

        let direction: String
        if minX < w / 3 { direction = "left" }
        else if minX > (w * 2) / 3 { direction = "right" }
        else { direction = "center" }

        return AgentDepthPayload(
            grid5x5: grid,
            nearestObstacleCM: minDist.isFinite ? Int(minDist * 100) : 500,
            nearestObstacleDirection: direction,
            clearPathAheadCM: corrMin.isFinite ? Int(corrMin * 100) : 500,
            lidarAvailable: true
        )
    }

    private func medianPatch(buf: RotatedDepthBuffer, cx: Int, cy: Int) -> (Float, UInt8) {
        var samples: [(Float, UInt8)] = []
        for dy in -1...1 {
            for dx in -1...1 {
                let (d, c) = buf.sample(x: cx + dx, y: cy + dy)
                if d > 0.1 { samples.append((d, c)) }
            }
        }
        guard !samples.isEmpty else { return (0, 0) }
        samples.sort { $0.0 < $1.0 }
        return samples[samples.count / 2]
    }
}

// MARK: - ARSessionDelegate

extension DepthCaptureManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lock.withLock {
            latestFrame = frame
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        AppLog.debug("[Depth] Tracking: \(camera.trackingState)")
    }
}
