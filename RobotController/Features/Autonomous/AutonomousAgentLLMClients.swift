import Foundation

struct AgentLLMRequestContext {
    let history: [AgentHistoryEntry]
    let task: String
    let step: Int
    let lastActionLog: String
    let lastDepthText: String
    let lastPhoto: String?
    let navigationState: AgentNavigationState
    let maxSteps: Int
}

protocol AgentLLMTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionAgentLLMTransport: AgentLLMTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

protocol AgentLLMClient {
    func nextStep(for context: AgentLLMRequestContext) async throws -> AgentStep
}

struct DefaultAgentLLMClient: AgentLLMClient {
    private let apiKey: String
    private let model: String
    private let backend: AgentBackend
    private let transport: any AgentLLMTransport

    init(
        apiKey: String,
        model: String,
        backend: AgentBackend,
        transport: any AgentLLMTransport = URLSessionAgentLLMTransport()
    ) {
        self.apiKey = apiKey
        self.model = model
        self.backend = backend
        self.transport = transport
    }

    func nextStep(for context: AgentLLMRequestContext) async throws -> AgentStep {
        switch backend {
        case .openAI:
            let messages = try AgentPromptBuilder.openAIMessages(
                history: context.history,
                task: context.task,
                step: context.step,
                lastActionLog: context.lastActionLog,
                lastDepthText: context.lastDepthText,
                lastPhoto: context.lastPhoto,
                navigationState: context.navigationState,
                maxSteps: context.maxSteps
            )
            let request = try AgentOpenAIClient.makeRequest(apiKey: apiKey, model: model, messages: messages)
            let (data, response) = try await transport.data(for: request)
            return try AgentOpenAIClient.decodeStep(from: data, response: response, step: context.step)

        case .gemini:
            let contents = try AgentPromptBuilder.geminiContents(
                history: context.history,
                task: context.task,
                step: context.step,
                lastActionLog: context.lastActionLog,
                lastDepthText: context.lastDepthText,
                lastPhoto: context.lastPhoto,
                navigationState: context.navigationState,
                maxSteps: context.maxSteps
            )
            let request = try AgentGeminiClient.makeRequest(apiKey: apiKey, model: model, contents: contents)
            let (data, response) = try await transport.data(for: request)
            return try AgentGeminiClient.decodeStep(from: data, response: response, step: context.step)
        }
    }
}

enum AgentOpenAIClient {
    static func makeRequest(
        apiKey: String,
        model: String,
        messages: [[String: Any]]
    ) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "agent_step",
                    "strict": false,
                    "schema": AgentSchema.schemaDict
                ]
            ] as [String: Any],
            "max_completion_tokens": 16000
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func decodeStep(from data: Data, response: URLResponse, step: Int) throws -> AgentStep {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let err = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiErrorDetail((response as? HTTPURLResponse)?.statusCode ?? 0, err)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }

        let choices = json["choices"] as? [[String: Any]]
        let choice = choices?.first
        let message = choice?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? ""
        let refusal = message?["refusal"] as? String
        let finishReason = choice?["finish_reason"] as? String

        let usage = json["usage"] as? [String: Any]
        let tokens = usage?["total_tokens"] as? Int ?? 0
        AppLog.debug("[Agent] Step \(step): \(tokens) tokens, finish=\(finishReason ?? "?"), content=\(content.count) chars")

        if let refusal {
            AppLog.error("[Agent] Refusal: \(refusal)")
            throw LLMError.apiErrorDetail(0, "Model refused: \(refusal)")
        }

        if content.isEmpty {
            AppLog.error("[Agent] Empty content. Full response: \(String(data: data, encoding: .utf8)?.prefix(1000) ?? "")")
            throw LLMError.invalidResponse
        }

        return try JSONDecoder().decode(AgentStep.self, from: Data(content.utf8))
    }
}

enum AgentGeminiClient {
    static func makeRequest(
        apiKey: String,
        model: String,
        contents: [[String: Any]]
    ) throws -> URLRequest {
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": AgentSchema.systemPrompt]]],
            "contents": contents,
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": AgentSchema.geminiSchemaDict,
                "maxOutputTokens": 2048
            ] as [String: Any]
        ]

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func decodeStep(from data: Data, response: URLResponse, step: Int) throws -> AgentStep {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let err = String(data: data, encoding: .utf8) ?? ""
            AppLog.error("[Agent/Gemini] Error: \(err.prefix(500))")
            throw LLMError.apiErrorDetail((response as? HTTPURLResponse)?.statusCode ?? 0, err)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }

        let candidates = json["candidates"] as? [[String: Any]]
        let contentObj = candidates?.first?["content"] as? [String: Any]
        let parts = contentObj?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String ?? ""
        let usage = json["usageMetadata"] as? [String: Any]
        let tokens = usage?["totalTokenCount"] as? Int ?? 0

        AppLog.debug("[Agent/Gemini] Step \(step): \(tokens) tokens, content=\(text.count) chars")

        if text.isEmpty {
            AppLog.error("[Agent/Gemini] Empty. Raw: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
            throw LLMError.invalidResponse
        }

        return try JSONDecoder().decode(AgentStep.self, from: Data(text.utf8))
    }
}
