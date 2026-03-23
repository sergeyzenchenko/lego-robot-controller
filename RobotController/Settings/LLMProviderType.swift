import Foundation

// MARK: - Provider Type

enum LLMProviderType: String, CaseIterable, RawRepresentable {
    case onDevice = "On-Device"
    case openAI = "OpenAI"
    case gemini = "Gemini"
}

// MARK: - Agent Backend

enum AgentBackend {
    case openAI
    case gemini
}
