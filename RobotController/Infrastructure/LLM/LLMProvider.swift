import Foundation

// MARK: - LLM Provider Protocol

struct LLMResponse {
    let plan: RobotPlan
    let estimatedTokens: Int
    let duration: Duration
}

@MainActor
protocol LLMProvider {
    var isReady: Bool { get }
    func warmUp() async
    func generatePlan(for prompt: String) async throws -> LLMResponse
    func resetContext()
}
