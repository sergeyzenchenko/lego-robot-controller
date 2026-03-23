import Foundation

// MARK: - OpenAI Provider (URLSession, no dependencies)

@MainActor
final class OpenAILLMProvider: LLMProvider, ObservableObject {
    @Published private(set) var isReady = false

    private let apiKey: String
    private let model: String
    private var history: [[String: Any]] = []
    private static let maxHistoryMessages = 40 // 20 pairs

    private static let systemPrompt = """
        You control a tank-tread robot. Two DC motors (left/right tracks), two LEDs.
        Respond ONLY with valid JSON matching the schema. No other text.
        First classify intent, then reason briefly (1-2 sentences), then generate actions.
        Examples:
        - "drive forward 3 seconds" → {"intent":"drive","reasoning":"Forward 3s.","actions":[{"moveForward":{"duration":3}}]}
        - "drive a square" → intent:shape, 8 actions: 4× moveForward+turnRight90
        - "turn on lights" → {"intent":"lights","reasoning":"LEDs on.","actions":[{"setLEDs":{"leftOn":true,"rightOn":true}}]}
        """

    init(apiKey: String, model: String = "gpt-5-nano") {
        self.apiKey = apiKey
        self.model = model
    }

    func warmUp() async {
        isReady = !apiKey.isEmpty
        AppLog.debug("[OpenAI] Ready (model: \(model), key: \(apiKey.prefix(8))...)")
    }

    func generatePlan(for prompt: String) async throws -> LLMResponse {
        history.append(["role": "user", "content": prompt])

        let body = makeRequestBody()
        let (data, httpResponse) = try await sendRequest(body: body)

        guard let http = httpResponse as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLog.error("[OpenAI] API error \(http.statusCode): \(errorText)")
            throw LLMError.apiError(http.statusCode, errorText)
        }

        let start = ContinuousClock.now // timing includes only parsing
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? ""
        let usage = json?["usage"] as? [String: Any]
        let completionTokens = usage?["completion_tokens"] as? Int ?? max(content.count / 4, 1)

        // Add assistant response to history
        history.append(["role": "assistant", "content": content])
        trimHistory()

        // Parse RobotPlan from JSON
        let planData = Data(content.utf8)
        let plan = try JSONDecoder().decode(RobotPlan.self, from: planData)

        // Use total request time for stats (re-measure including network)
        let elapsed = ContinuousClock.now - start

        return LLMResponse(plan: plan, estimatedTokens: completionTokens, duration: elapsed)
    }

    func resetContext() {
        history.removeAll()
        AppLog.debug("[OpenAI] Context reset")
    }

    // MARK: - Private

    private func makeRequestBody() -> [String: Any] {
        var messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPrompt]
        ]
        messages.append(contentsOf: history)

        return [
            "model": model,
            "messages": messages,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "robot_plan",
                    "strict": true,
                    "schema": Self.schema
                ]
            ] as [String: Any]
        ]
    }

    private func sendRequest(body: [String: Any]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: request)
    }

    private func trimHistory() {
        if history.count > Self.maxHistoryMessages {
            let excess = history.count - Self.maxHistoryMessages
            history.removeFirst(excess)
            AppLog.debug("[OpenAI] Trimmed \(excess) messages")
        }
    }

    // MARK: - JSON Schema (generated from @Schemable RobotPlan)

    private static let schema: [String: Any] = SchemaExport.toOpenAIStrictDict(RobotPlan.schema)
}

// MARK: - Extended errors

extension LLMError {
    static func apiError(_ code: Int, _ message: String) -> LLMError {
        .apiErrorDetail(code, message)
    }
}
