import SwiftUI

// MARK: - Settings View

struct LLMSettingsView: View {
    @ObservedObject var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Model", selection: $settings.providerType) {
                        ForEach(LLMProviderType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if settings.providerType == .openAI {
                    Section("OpenAI") {
                        SecureField("API Key", text: $settings.openAIKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()

                        Picker("Model", selection: $settings.openAIModel) {
                            Text("GPT-5 nano").tag("gpt-5-nano")
                            Text("GPT-4o mini").tag("gpt-4o-mini")
                            Text("GPT-4o").tag("gpt-4o")
                            Text("GPT-4.1 mini").tag("gpt-4.1-mini")
                            Text("GPT-4.1").tag("gpt-4.1")
                            Text("o4-mini").tag("o4-mini")
                        }
                    }
                }

                if settings.providerType == .gemini {
                    Section("Google Gemini") {
                        SecureField("API Key", text: $settings.geminiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()

                        Picker("Model", selection: $settings.geminiModel) {
                            Text("Gemini 3.1 Flash Lite").tag("gemini-3.1-flash-lite")
                            Text("Gemini 2.5 Flash").tag("gemini-2.5-flash")
                            Text("Gemini 2.5 Pro").tag("gemini-2.5-pro")
                            Text("Gemini 2.0 Flash").tag("gemini-2.0-flash")
                        }
                    }
                }

                if settings.providerType == .onDevice {
                    Section {
                        Label("Runs entirely on device. No API key needed.", systemImage: "iphone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
