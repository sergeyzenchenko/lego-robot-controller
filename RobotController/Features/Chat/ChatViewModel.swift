import Foundation
import SwiftUI

// MARK: - Chat View Model

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isResponding = false
    @Published var isModelReady = false

    private let provider: LLMProvider
    private let robotViewModel: RobotViewModel
    private lazy var executor = PlanExecutor(robotViewModel: robotViewModel)

    init(robotViewModel: RobotViewModel, provider: LLMProvider) {
        self.robotViewModel = robotViewModel
        self.provider = provider
    }

    func warmUp() {
        guard !isModelReady else { return }
        AppLog.debug("[LLM] warmUp called")
        Task {
            await provider.warmUp()
            isModelReady = provider.isReady
            AppLog.debug("[LLM] Ready: \(isModelReady)")
        }
    }

    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding, isModelReady else {
            AppLog.debug("[LLM] sendText blocked: empty=\(text.isEmpty) responding=\(isResponding) ready=\(isModelReady)")
            return
        }

        messages.append(ChatMessage(role: .user, text: trimmed))
        inputText = ""
        isResponding = true
        AppLog.debug("[LLM] Sending: \(trimmed)")

        Task {
            defer { isResponding = false }
            await respond(to: trimmed)
        }
    }

    func send() {
        sendText(inputText)
    }

    // MARK: - Respond

    private func respond(to text: String) async {
        do {
            let response = try await provider.generatePlan(for: text)
            let plan = response.plan

            let seconds = response.duration.components.seconds
            let ms = response.duration.components.attoseconds / 1_000_000_000_000_000
            let totalMs = seconds * 1000 + ms
            let tokPerSec = totalMs > 0 ? Double(response.estimatedTokens) / (Double(totalMs) / 1000.0) : 0

            AppLog.debug("[LLM] Plan: intent=\(plan.intent) actions=\(plan.actions.count), ~\(response.estimatedTokens) tok in \(totalMs)ms (\(String(format: "%.1f", tokPerSec)) tok/s)")
            AppLog.debug("[LLM] Reasoning: \(plan.reasoning)")

            messages.append(ChatMessage(role: .reasoning, text: plan.reasoning))

            let summary = describeActions(plan.actions)
            if !summary.isEmpty {
                messages.append(ChatMessage(role: .action, text: summary))
            }

            AppLog.debug("[LLM] Executing plan...")
            await executor.execute(plan)
            AppLog.debug("[LLM] Execution done")

            let stats = String(format: "\(plan.intent) · %d steps · ~%d tok · %.1fs · %.0f tok/s",
                               plan.actions.count, response.estimatedTokens, Double(totalMs) / 1000.0, tokPerSec)
            messages.append(ChatMessage(role: .stats, text: stats))

        } catch {
            AppLog.error("[LLM] Error: \(error)")
            messages.append(ChatMessage(role: .error, text: error.localizedDescription))
        }
    }

    // MARK: - Describe Actions

    private func describeActions(_ actions: [RobotAction]) -> String {
        actions.enumerated().map { i, action in
            let n = "\(i + 1). "
            switch action {
            case .moveForward(let p):
                return n + "Forward \(p.duration)s"
            case .moveBackward(let p):
                return n + "Backward \(p.duration)s"
            case .turnLeft90:
                return n + "Turn left 90°"
            case .turnRight90:
                return n + "Turn right 90°"
            case .turnAround:
                return n + "Turn around 180°"
            case .spin360:
                return n + "Spin 360°"
            case .stop:
                return n + "Stop"
            case .setLEDs(let p):
                return n + "LEDs: L=\(p.leftOn ? "on" : "off") R=\(p.rightOn ? "on" : "off")"
            }
        }.joined(separator: "\n")
    }
}
