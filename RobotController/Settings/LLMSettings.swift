import SwiftUI

// MARK: - Settings Storage

struct LLMProviderConfiguration: Equatable {
    let providerType: LLMProviderType
    let openAIKey: String
    let openAIModel: String
    let geminiKey: String
    let geminiModel: String
}

enum LLMProviderFactory {
    @MainActor
    static func makeProvider(from configuration: LLMProviderConfiguration) -> LLMProvider {
        switch configuration.providerType {
        case .onDevice:
            if #available(iOS 26.0, *) {
                return OnDeviceLLMProvider()
            } else {
                fatalError("On-device model requires iOS 26+")
            }
        case .openAI:
            return OpenAILLMProvider(apiKey: configuration.openAIKey, model: configuration.openAIModel)
        case .gemini:
            return GeminiLLMProvider(apiKey: configuration.geminiKey, model: configuration.geminiModel)
        }
    }
}

@MainActor
final class LLMSettings: ObservableObject {
    @AppStorage("llmProvider") var providerType: LLMProviderType = .onDevice
    @AppStorage("openAIKey") var openAIKey: String = ""
    @AppStorage("openAIModel") var openAIModel: String = "gpt-5-nano"
    @AppStorage("geminiKey") var geminiKey: String = ""
    @AppStorage("geminiModel") var geminiModel: String = "gemini-3.1-flash-lite"

    func makeProvider(for robotViewModel: RobotViewModel) -> LLMProvider {
        LLMProviderFactory.makeProvider(from: providerConfiguration)
    }

    var providerConfiguration: LLMProviderConfiguration {
        LLMProviderConfiguration(
            providerType: providerType,
            openAIKey: openAIKey,
            openAIModel: openAIModel,
            geminiKey: geminiKey,
            geminiModel: geminiModel
        )
    }

    /// The API key to use for agent/TTS (prefers OpenAI, falls back to Gemini)
    var agentAPIKey: String {
        if !openAIKey.isEmpty { return openAIKey }
        return geminiKey
    }

    /// The model to use for the autonomous agent
    var agentModel: String {
        switch providerType {
        case .gemini: return geminiModel
        case .openAI: return openAIModel
        default: return openAIModel.isEmpty ? geminiModel : openAIModel
        }
    }

    /// Which API backend the autonomous agent should use
    var agentBackend: AgentBackend {
        switch providerType {
        case .gemini: return .gemini
        default: return .openAI
        }
    }
}
