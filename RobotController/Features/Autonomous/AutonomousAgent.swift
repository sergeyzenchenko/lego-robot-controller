import Foundation
import SwiftUI

// MARK: - Autonomous Agent

@MainActor
final class AutonomousAgent: ObservableObject {
    @Published var status: AgentStatus = .idle
    @Published var stepCount = 0
    @Published var currentThinking = ""
    @Published var currentSummary = ""
    @Published var log: [LogEntry] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let step: Int
        let type: LogType
        let text: String

        enum LogType { case thinking, action, observation, decision, photo, error, tts }
    }

    private let robotViewModel: RobotViewModel
    private let openAIKey: String // always OpenAI key, for TTS
    private let llmClient: any AgentLLMClient
    private let maxSteps: Int
    private var runTask: Task<Void, Never>?
    private var history: [AgentHistoryEntry] = []
    private var navigationState = AgentNavigationState()

    init(
        robotViewModel: RobotViewModel,
        apiKey: String,
        openAIKey: String = "",
        model: String = "gpt-4.1",
        backend: AgentBackend = .openAI,
        maxSteps: Int = 20,
        llmClient: (any AgentLLMClient)? = nil
    ) {
        self.robotViewModel = robotViewModel
        self.openAIKey = openAIKey.isEmpty ? apiKey : openAIKey
        self.llmClient = llmClient ?? DefaultAgentLLMClient(apiKey: apiKey, model: model, backend: backend)
        self.maxSteps = maxSteps
    }

    func start(task: String) {
        guard status == .idle || status == .done("") || isFinalState else { return }
        reset()
        status = .running
        addLog(step: 0, type: .thinking, text: "Task: \(task)")

        runTask = Task { [weak self] in
            await self?.agentLoop(task: task)
        }
    }

    func stop() {
        runTask?.cancel()
        robotViewModel.sendMotor(.stop)
        status = .idle
        addLog(step: stepCount, type: .decision, text: "Cancelled by user")
    }

    func resumeWithUserInput(_ input: String) {
        guard case .paused = status else { return }
        status = .running
        // Input gets picked up in the loop via userResponse
        userResponse = input
    }

    private var userResponse: String?

    // MARK: - Agent Loop

    private func agentLoop(task: String) async {
        let executor = AgentExecutor(robotViewModel: robotViewModel)

        // Initial observation
        addLog(step: 0, type: .observation, text: "Taking initial photo...")
        let initialPhoto = try? await robotViewModel.capturePhoto()
        let initialDepth = await robotViewModel.captureDepth()

        var lastPhoto = initialPhoto?.base64EncodedString()
        var lastDepthText = initialDepth.textDescription
        var lastActionLog = "None (initial observation)"

        for step in 1...maxSteps {
            guard !Task.isCancelled else { break }
            stepCount = step

            // Build messages and call LLM
            addLog(step: step, type: .thinking, text: "Planning step \(step)...")

            let agentStep: AgentStep
            do {
                agentStep = try await callLLM(
                    task: task,
                    step: step,
                    lastActionLog: lastActionLog,
                    lastDepthText: lastDepthText,
                    lastPhoto: lastPhoto
                )
            } catch {
                addLog(step: step, type: .error, text: "LLM error: \(error.localizedDescription)")
                status = .failed("LLM error: \(error.localizedDescription)")
                break
            }

            currentThinking = agentStep.thinking
            currentSummary = agentStep.summary
            addLog(step: step, type: .thinking, text: agentStep.thinking)

            // Execute actions
            if !agentStep.actions.isEmpty {
                let actionDesc = agentStep.actions.map { $0.type.rawValue }.joined(separator: ", ")
                addLog(step: step, type: .action, text: actionDesc)

                let result = await executor.execute(actions: agentStep.actions)

                navigationState.apply(actions: agentStep.actions)

                lastActionLog = result.log.joined(separator: ". ")
                lastPhoto = result.photoBase64
                lastDepthText = result.depthText

                addLog(step: step, type: .observation, text: "Clear: \(AgentPromptBuilder.clearPathDistance(from: result.depthText))cm ahead")

                // Add look photos to history
                for (dir, _) in result.lookPhotos {
                    addLog(step: step, type: .photo, text: "Scanned \(dir)")
                }

                // Save history
                history.append(AgentHistoryEntry(
                    step: step,
                    thinking: agentStep.thinking,
                    actionLog: lastActionLog,
                    decision: agentStep.decision,
                    observation: lastDepthText,
                    photoBase64: lastPhoto,
                    summary: agentStep.summary,
                    posX: navigationState.posX,
                    posY: navigationState.posY,
                    heading: navigationState.heading
                ))
            }

            // Handle decision
            addLog(step: step, type: .decision, text: agentStep.decision.rawValue)

            switch agentStep.decision {
            case .done:
                status = .done(agentStep.summary)
                addLog(step: step, type: .tts, text: agentStep.summary)
                await robotViewModel.speak(agentStep.summary, apiKey: openAIKey)
                return

            case .stuck:
                status = .failed(agentStep.summary)
                addLog(step: step, type: .tts, text: agentStep.summary)
                await robotViewModel.speak(agentStep.summary, apiKey: openAIKey)
                return

            case .ask_user:
                status = .paused(agentStep.summary)
                addLog(step: step, type: .tts, text: agentStep.summary)
                await robotViewModel.speak(agentStep.summary, apiKey: openAIKey)

                // Wait for user response
                while userResponse == nil && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard let response = userResponse else { break }
                userResponse = nil
                lastActionLog = "User said: \(response)"

            case .continue:
                // Speak brief status every 3 steps
                if step % 3 == 0 {
                    addLog(step: step, type: .tts, text: agentStep.summary)
                    await robotViewModel.speak(agentStep.summary, apiKey: openAIKey)
                }
                continue
            }
        }

        if status == .running {
            status = .failed("Reached maximum \(maxSteps) steps")
            await robotViewModel.speak("I've reached my step limit. Stopping here.", apiKey: openAIKey)
        }
    }

    // MARK: - LLM Call

    private func callLLM(
        task: String,
        step: Int,
        lastActionLog: String,
        lastDepthText: String,
        lastPhoto: String?
    ) async throws -> AgentStep {
        let context = AgentLLMRequestContext(
            history: history,
            task: task,
            step: step,
            lastActionLog: lastActionLog,
            lastDepthText: lastDepthText,
            lastPhoto: lastPhoto,
            navigationState: navigationState,
            maxSteps: maxSteps
        )
        return try await llmClient.nextStep(for: context)
    }

    // MARK: - Helpers

    private func reset() {
        stepCount = 0
        currentThinking = ""
        currentSummary = ""
        log.removeAll()
        history.removeAll()
        navigationState.reset()
        userResponse = nil
    }

    private var isFinalState: Bool {
        switch status {
        case .done, .failed: return true
        default: return false
        }
    }

    private func addLog(step: Int, type: LogEntry.LogType, text: String) {
        log.append(LogEntry(step: step, type: type, text: text))
    }
}
