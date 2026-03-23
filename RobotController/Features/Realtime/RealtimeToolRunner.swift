import Foundation

struct RealtimeToolExecutionResult: Equatable {
    let textResult: String
    let photoBase64: String?
}

struct RealtimeObservationCaptureResult: Equatable {
    let photoBase64: String?
    let depthText: String
}

enum RealtimeToolResponseBuilder {
    static func actResponse(actionCount: Int, result: RobotExecutionResult) -> String {
        let summary = result.log.joined(separator: ". ")
        return """
            Executed \(actionCount) actions: \(summary).
            A photo of the current view is attached.
            \(result.depthText)
            Analyze the photo and depth data. Describe what you see briefly.
            Decide if the task is complete or if more actions are needed.
            If an obstacle is close (<30cm), warn the user.
            """
    }

    static func lookResponse(depthText: String) -> String {
        """
            Photo taken without moving. The photo is attached.
            \(depthText)
            Describe what you see briefly using both the photo and depth data.
            If the user asked about the environment, answer based on what you see.
            If obstacles or hazards are close, mention them with distances.
            """
    }

    static func depthText(from depth: AgentDepthPayload) -> String {
        if depth.lidarAvailable {
            return "LiDAR depth data:\n\(depth.textDescription)"
        }
        return "LiDAR depth: unavailable on this device."
    }

    static func depthProgressMessage(from depth: AgentDepthPayload) -> String? {
        guard depth.lidarAvailable else { return nil }
        return "📐 Depth: nearest \(depth.nearestObstacleCM)cm \(depth.nearestObstacleDirection), clear \(depth.clearPathAheadCM)cm"
    }
}

enum RealtimeToolRunner {
    @MainActor
    static func execute(
        name: String,
        arguments: String,
        robotViewModel: RobotViewModel?,
        onProgress: @escaping @MainActor (String) -> Void
    ) async -> RealtimeToolExecutionResult {
        if name == "look" {
            return await executeLook(robotViewModel: robotViewModel, onProgress: onProgress)
        }

        guard name == "act" else {
            return RealtimeToolExecutionResult(textResult: "Unknown tool: \(name)", photoBase64: nil)
        }
        guard let robotViewModel else {
            return RealtimeToolExecutionResult(textResult: "Robot not connected", photoBase64: nil)
        }

        let params: ActToolParams
        do {
            params = try JSONDecoder().decode(ActToolParams.self, from: Data(arguments.utf8))
        } catch {
            AppLog.error("[Realtime] Failed to decode act params: \(error)")
            return RealtimeToolExecutionResult(textResult: "Failed to parse action parameters", photoBase64: nil)
        }

        AppLog.debug("[Realtime] Act: \(params.reasoning)")

        for (index, action) in params.actions.enumerated() {
            guard !Task.isCancelled else { break }
            AppLog.debug("[Realtime] Step \(index + 1): \(action.type.rawValue)")
            await onProgress("\(index + 1). \(action.type.rawValue)")
        }

        let result = await robotViewModel.execute(
            commands: params.actions.robotCommands(initialLEDState: robotViewModel.ledState),
            capturesFinalObservation: true
        )

        return RealtimeToolExecutionResult(
            textResult: RealtimeToolResponseBuilder.actResponse(actionCount: params.actions.count, result: result),
            photoBase64: result.photoBase64
        )
    }

    @MainActor
    private static func executeLook(
        robotViewModel: RobotViewModel?,
        onProgress: @escaping @MainActor (String) -> Void
    ) async -> RealtimeToolExecutionResult {
        await onProgress("👁 Looking...")

        let observation = await captureObservation(robotViewModel: robotViewModel, onProgress: onProgress)

        return RealtimeToolExecutionResult(
            textResult: RealtimeToolResponseBuilder.lookResponse(depthText: observation.depthText),
            photoBase64: observation.photoBase64
        )
    }

    @MainActor
    private static func captureObservation(
        robotViewModel: RobotViewModel?,
        onProgress: @escaping @MainActor (String) -> Void
    ) async -> RealtimeObservationCaptureResult {
        guard let robotViewModel else {
            return RealtimeObservationCaptureResult(photoBase64: nil, depthText: "Robot perception unavailable.")
        }

        var photoBase64: String?
        do {
            let imageData = try await robotViewModel.capturePhoto()
            photoBase64 = imageData.base64EncodedString()
            await onProgress("📷 Photo")
        } catch {
            AppLog.error("[Realtime] Camera error: \(error)")
        }

        let depth = await robotViewModel.captureDepth()
        if let progress = RealtimeToolResponseBuilder.depthProgressMessage(from: depth) {
            await onProgress(progress)
        }

        return RealtimeObservationCaptureResult(
            photoBase64: photoBase64,
            depthText: RealtimeToolResponseBuilder.depthText(from: depth)
        )
    }
}
