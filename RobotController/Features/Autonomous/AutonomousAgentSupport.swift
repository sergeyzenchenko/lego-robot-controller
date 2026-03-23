import Foundation

struct AgentNavigationState {
    var posX: Double = 0
    var posY: Double = 0
    var heading: Double = 0

    mutating func apply(actions: [AgentAction]) {
        for action in actions {
            switch action.type {
            case .move:
                let cm = Double(action.distance_cm ?? 0)
                let dir = action.direction == .backward ? -1.0 : 1.0
                let rad = heading * .pi / 180
                posX += cos(rad) * cm * dir
                posY += sin(rad) * cm * dir
            case .turn:
                let deg = Double(action.degrees ?? 0)
                if action.direction == .left {
                    heading -= deg
                } else {
                    heading += deg
                }
                heading = heading.truncatingRemainder(dividingBy: 360)
            case .look:
                break
            default:
                break
            }
        }
    }

    mutating func reset() {
        posX = 0
        posY = 0
        heading = 0
    }
}

enum AgentPromptBuilder {
    static func openAIMessages(
        history: [AgentHistoryEntry],
        task: String,
        step: Int,
        lastActionLog: String,
        lastDepthText: String,
        lastPhoto: String?,
        navigationState: AgentNavigationState,
        maxSteps: Int
    ) throws -> [[String: Any]] {
        var messages: [[String: Any]] = [
            ["role": "system", "content": AgentSchema.systemPrompt]
        ]

        let recentCount = 4
        for (i, entry) in history.enumerated() {
            let isRecent = i >= history.count - recentCount
            messages.append(["role": "user", "content": openAIObservationContent(for: entry, includesPhoto: isRecent)])
            messages.append(["role": "assistant", "content": try assistantHistoryContent(for: entry)])
        }

        messages.append([
            "role": "user",
            "content": currentOpenAIObservationContent(
                task: task,
                step: step,
                lastActionLog: lastActionLog,
                lastDepthText: lastDepthText,
                lastPhoto: lastPhoto,
                navigationState: navigationState,
                maxSteps: maxSteps
            )
        ])

        return messages
    }

    static func geminiContents(
        history: [AgentHistoryEntry],
        task: String,
        step: Int,
        lastActionLog: String,
        lastDepthText: String,
        lastPhoto: String?,
        navigationState: AgentNavigationState,
        maxSteps: Int
    ) throws -> [[String: Any]] {
        var contents: [[String: Any]] = []
        let recentCount = 4

        for (i, entry) in history.enumerated() {
            let isRecent = i >= history.count - recentCount
            contents.append(["role": "user", "parts": geminiObservationParts(for: entry, includesPhoto: isRecent)])
            contents.append(["role": "model", "parts": [["text": try assistantHistoryContent(for: entry)]]])
        }

        contents.append([
            "role": "user",
            "parts": currentGeminiObservationParts(
                task: task,
                step: step,
                lastActionLog: lastActionLog,
                lastDepthText: lastDepthText,
                lastPhoto: lastPhoto,
                navigationState: navigationState,
                maxSteps: maxSteps
            )
        ])

        return contents
    }

    static func clearPathDistance(from depthText: String) -> String {
        if let range = depthText.range(of: "Clear path ahead: ") {
            let start = range.upperBound
            if let end = depthText[start...].firstIndex(of: "c") {
                return String(depthText[start..<end])
            }
        }
        return "?"
    }

    private static func openAIObservationContent(
        for entry: AgentHistoryEntry,
        includesPhoto: Bool
    ) -> [[String: Any]] {
        var content: [[String: Any]] = [
            ["type": "text", "text": historyObservationText(for: entry)]
        ]
        if includesPhoto, let photo = entry.photoBase64 {
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(photo)"]
            ] as [String: Any])
        }
        return content
    }

    private static func geminiObservationParts(
        for entry: AgentHistoryEntry,
        includesPhoto: Bool
    ) -> [[String: Any]] {
        var parts: [[String: Any]] = [
            ["text": historyObservationText(for: entry)]
        ]
        if includesPhoto, let photo = entry.photoBase64 {
            parts.insert(["inline_data": ["mime_type": "image/jpeg", "data": photo] as [String: Any]], at: 0)
        }
        return parts
    }

    private static func assistantHistoryContent(for entry: AgentHistoryEntry) throws -> String {
        let stepJSON = try JSONEncoder().encode(AgentStep(
            thinking: entry.thinking,
            summary: entry.summary,
            actions: [],
            decision: entry.decision
        ))
        return String(data: stepJSON, encoding: .utf8) ?? ""
    }

    private static func currentOpenAIObservationContent(
        task: String,
        step: Int,
        lastActionLog: String,
        lastDepthText: String,
        lastPhoto: String?,
        navigationState: AgentNavigationState,
        maxSteps: Int
    ) -> [[String: Any]] {
        var content: [[String: Any]] = [
            ["type": "text", "text": currentObservationText(
                task: task,
                step: step,
                lastActionLog: lastActionLog,
                lastDepthText: lastDepthText,
                navigationState: navigationState,
                maxSteps: maxSteps
            )]
        ]
        if let photo = lastPhoto {
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(photo)"]
            ] as [String: Any])
        }
        return content
    }

    private static func currentGeminiObservationParts(
        task: String,
        step: Int,
        lastActionLog: String,
        lastDepthText: String,
        lastPhoto: String?,
        navigationState: AgentNavigationState,
        maxSteps: Int
    ) -> [[String: Any]] {
        var parts: [[String: Any]] = [
            ["text": currentObservationText(
                task: task,
                step: step,
                lastActionLog: lastActionLog,
                lastDepthText: lastDepthText,
                navigationState: navigationState,
                maxSteps: maxSteps
            )]
        ]
        if let photo = lastPhoto {
            parts.insert(["inline_data": ["mime_type": "image/jpeg", "data": photo] as [String: Any]], at: 0)
        }
        return parts
    }

    private static func historyObservationText(for entry: AgentHistoryEntry) -> String {
        """
        Step \(entry.step) result: \(entry.actionLog)
        Position: x=\(Int(entry.posX))cm y=\(Int(entry.posY))cm heading=\(Int(entry.heading))°
        \(entry.observation)
        """
    }

    private static func currentObservationText(
        task: String,
        step: Int,
        lastActionLog: String,
        lastDepthText: String,
        navigationState: AgentNavigationState,
        maxSteps: Int
    ) -> String {
        """
        Task: \(task)
        Step \(step) observation (after: \(lastActionLog)):
        Position: x=\(Int(navigationState.posX))cm y=\(Int(navigationState.posY))cm heading=\(Int(navigationState.heading))°
        Steps remaining: \(maxSteps - step)
        \(lastDepthText)
        """
    }
}
