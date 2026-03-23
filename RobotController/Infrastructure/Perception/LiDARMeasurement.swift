import Foundation

// MARK: - LiDAR-based movement measurement

enum LiDARMeasurement {

    /// Estimate actual forward/backward distance traveled by comparing
    /// center corridor depth before and after movement.
    /// Returns measured distance in cm (positive = forward progress).
    static func measureDistance(before: AgentDepthPayload, after: AgentDepthPayload, direction: String) -> Int? {
        guard before.lidarAvailable && after.lidarAvailable else { return nil }

        let beforeDist = before.clearPathAheadCM
        let afterDist = after.clearPathAheadCM

        guard beforeDist > 20 && afterDist > 20 else { return nil } // dead zone

        if direction == "forward" {
            // Moving forward: distance ahead should decrease
            let moved = beforeDist - afterDist
            // Sanity check: should be positive and reasonable
            guard moved > 0 && moved < 200 else { return nil }
            return moved
        } else {
            // Moving backward: distance ahead should increase
            let moved = afterDist - beforeDist
            guard moved > 0 && moved < 200 else { return nil }
            return moved
        }
    }

    /// Estimate actual turn angle by comparing depth grid columns before and after.
    /// Uses cross-correlation of the middle row to find the pixel shift,
    /// then converts to degrees based on the camera's horizontal FOV.
    ///
    /// Returns estimated angle in degrees (positive = turned right).
    static func measureTurn(before: AgentDepthPayload, after: AgentDepthPayload) -> Int? {
        guard before.lidarAvailable && after.lidarAvailable else { return nil }
        guard before.grid5x5.count == 5 && after.grid5x5.count == 5 else { return nil }

        // Use the middle row (index 2) as the reference scanline
        let beforeRow = before.grid5x5[2]
        let afterRow = after.grid5x5[2]

        guard beforeRow.count == 5 && afterRow.count == 5 else { return nil }

        // Extract depth values (use 0 for nil)
        let bVals = beforeRow.map { $0.distanceCM ?? 0 }
        let aVals = afterRow.map { $0.distanceCM ?? 0 }

        // Skip if too many zero readings
        let bValid = bVals.filter { $0 > 20 }.count
        let aValid = aVals.filter { $0 > 20 }.count
        guard bValid >= 3 && aValid >= 3 else { return nil }

        // Cross-correlate: try shifts from -3 to +3
        // Each column covers ~8° of the ~40° FOV
        var bestShift = 0
        var bestScore = Int.max

        for shift in -3...3 {
            var score = 0
            var count = 0
            for i in 0..<5 {
                let j = i + shift
                guard j >= 0 && j < 5 else { continue }
                let bv = bVals[i]
                let av = aVals[j]
                guard bv > 20 && av > 20 else { continue }
                score += abs(bv - av)
                count += 1
            }
            if count > 0 {
                let normalized = score / count
                if normalized < bestScore {
                    bestScore = normalized
                    bestShift = shift
                }
            }
        }

        // Each column ≈ 8° (40° FOV / 5 columns)
        let degreesPerColumn = 8
        let measuredAngle = bestShift * degreesPerColumn

        // Only return if we have a meaningful shift and the match quality is decent
        // (bestScore < 30 means the shifted rows match within 30cm average)
        guard bestScore < 50 else { return nil }

        return measuredAngle
    }

    /// Format a measurement comparison string for the log
    static func formatMoveLog(direction: String, requestedCM: Int, measuredCM: Int?) -> String {
        if let measured = measuredCM {
            let diff = measured - requestedCM
            let diffStr = diff >= 0 ? "+\(diff)" : "\(diff)"
            return "Moved \(direction) \(requestedCM)cm (LiDAR: \(measured)cm, \(diffStr)cm)"
        }
        return "Moved \(direction) \(requestedCM)cm (LiDAR: n/a)"
    }

    static func formatTurnLog(direction: String, requestedDeg: Int, measuredDeg: Int?) -> String {
        if let measured = measuredDeg {
            let actual = abs(measured)
            let diff = actual - requestedDeg
            let diffStr = diff >= 0 ? "+\(diff)" : "\(diff)"
            return "Turned \(direction) \(requestedDeg)° (LiDAR: ~\(actual)°, \(diffStr)°)"
        }
        return "Turned \(direction) \(requestedDeg)° (LiDAR: n/a)"
    }
}
