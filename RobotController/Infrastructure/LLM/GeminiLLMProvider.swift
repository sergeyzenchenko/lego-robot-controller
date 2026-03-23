import Foundation

// MARK: - Gemini LLM Provider (REST API, zero dependencies)

@MainActor
final class GeminiLLMProvider: LLMProvider, ObservableObject {
    @Published private(set) var isReady = false

    private let apiKey: String
    private let model: String
    private var history: [[String: Any]] = [] // Gemini conversation history
    private static let maxHistoryMessages = 20

    private static let systemPrompt = """
        You control a tank-tread robot. Two DC motors (left/right tracks), two LEDs.
        Respond ONLY with valid JSON matching the schema. No other text.
        First classify intent, then reason briefly (1-2 sentences), then generate actions.
        Examples:
        - "drive forward 3 seconds" → {"intent":"drive","reasoning":"Forward 3s.","actions":[{"moveForward":{"duration":3}}]}
        - "drive a square" → intent:shape, 8 actions: 4× moveForward+turnRight90
        - "turn on lights" → {"intent":"lights","reasoning":"LEDs on.","actions":[{"setLEDs":{"leftOn":true,"rightOn":true}}]}
        """

    init(apiKey: String, model: String = "gemini-3.1-flash-lite") {
        self.apiKey = apiKey
        self.model = model
    }

    func warmUp() async {
        isReady = !apiKey.isEmpty
        AppLog.debug("[Gemini] Ready (model: \(model))")
    }

    func generatePlan(for prompt: String) async throws -> LLMResponse {
        // Add user message to history
        history.append([
            "role": "user",
            "parts": [["text": prompt]]
        ])

        let body = makeRequestBody()
        let start = ContinuousClock.now
        let (data, httpResponse) = try await sendRequest(body: body)

        guard let http = httpResponse as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLog.error("[Gemini] API error \(http.statusCode): \(errorText)")
            throw LLMError.apiErrorDetail(http.statusCode, errorText)
        }

        let elapsed = ContinuousClock.now - start

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String ?? ""
        let usage = json?["usageMetadata"] as? [String: Any]
        let tokens = usage?["totalTokenCount"] as? Int ?? max(text.count / 4, 1)

        // Add model response to history
        history.append([
            "role": "model",
            "parts": [["text": text]]
        ])
        trimHistory()

        let planData = Data(text.utf8)
        let plan = try JSONDecoder().decode(RobotPlan.self, from: planData)

        return LLMResponse(plan: plan, estimatedTokens: tokens, duration: elapsed)
    }

    func resetContext() {
        history.removeAll()
        AppLog.debug("[Gemini] Context reset")
    }

    // MARK: - Private

    private func makeRequestBody() -> [String: Any] {
        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": Self.systemPrompt]]
            ],
            "contents": history,
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": Self.robotPlanSchema,
                "maxOutputTokens": 2048
            ] as [String: Any]
        ]
        return body
    }

    private func sendRequest(body: [String: Any]) async throws -> (Data, URLResponse) {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: request)
    }

    private func trimHistory() {
        if history.count > Self.maxHistoryMessages {
            let excess = history.count - Self.maxHistoryMessages
            history.removeFirst(excess)
        }
    }

    // MARK: - Gemini JSON Schema (generated from @Schemable RobotPlan, uppercased types)

    private static let robotPlanSchema: [String: Any] = SchemaExport.toGeminiDict(RobotPlan.schema)
}
