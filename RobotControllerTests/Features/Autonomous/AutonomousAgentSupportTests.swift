import XCTest
@testable import RobotController

final class AutonomousAgentSupportTests: XCTestCase {

    func testAgentNavigationStateAppliesMoveAndTurn() {
        var state = AgentNavigationState()
        state.apply(actions: [
            AgentAction(type: .move, direction: .forward, distance_cm: 10, degrees: nil, status: nil, led: nil, seconds: nil),
            AgentAction(type: .turn, direction: .right, distance_cm: nil, degrees: 90, status: nil, led: nil, seconds: nil),
            AgentAction(type: .move, direction: .forward, distance_cm: 5, degrees: nil, status: nil, led: nil, seconds: nil)
        ])

        XCTAssertEqual(state.posX.rounded(), 10)
        XCTAssertEqual(state.posY.rounded(), 5)
        XCTAssertEqual(state.heading, 90)
    }

    func testAgentPromptBuilderExtractsClearPathDistance() {
        let depthText = "Nearest obstacle: 42cm\nClear path ahead: 88cm\nLiDAR available"
        XCTAssertEqual(AgentPromptBuilder.clearPathDistance(from: depthText), "88")
        XCTAssertEqual(AgentPromptBuilder.clearPathDistance(from: "unknown"), "?")
    }

    func testAgentOpenAIClientBuildsChatCompletionRequest() throws {
        let request = try AgentOpenAIClient.makeRequest(
            apiKey: "openai-key",
            model: "gpt-4.1",
            messages: [["role": "system", "content": "hello"]]
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-key")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "gpt-4.1")
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 16000)
        XCTAssertNotNil(json["response_format"] as? [String: Any])
        XCTAssertEqual((json["messages"] as? [[String: Any]])?.count, 1)
    }

    func testAgentOpenAIClientDecodesChatCompletionResponse() throws {
        let content = """
        {"thinking":"Scan left","summary":"Continuing","actions":[],"decision":"continue"}
        """
        let data = try XCTUnwrap("""
        {
          "choices": [
            {
              "message": {
                "content": \(String(reflecting: content))
              },
              "finish_reason": "stop"
            }
          ],
          "usage": {
            "total_tokens": 321
          }
        }
        """.data(using: .utf8))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))

        let step = try AgentOpenAIClient.decodeStep(from: data, response: response, step: 1)

        XCTAssertEqual(step.summary, "Continuing")
        XCTAssertEqual(step.decision, .continue)
        XCTAssertEqual(step.actions.count, 0)
    }

    func testAgentGeminiClientBuildsGenerateContentRequest() throws {
        let request = try AgentGeminiClient.makeRequest(
            apiKey: "gemini-key",
            model: "gemini-2.5-flash",
            contents: [["role": "user", "parts": [["text": "hello"]]]]
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-key")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertNotNil(json["systemInstruction"] as? [String: Any])
        XCTAssertEqual((json["contents"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(
            ((json["generationConfig"] as? [String: Any])?["responseMimeType"] as? String),
            "application/json"
        )
    }

    func testAgentGeminiClientDecodesGenerateContentResponse() throws {
        let text = """
        {"thinking":"Path is clear","summary":"Moving on","actions":[],"decision":"done"}
        """
        let data = try XCTUnwrap("""
        {
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": \(String(reflecting: text))
                  }
                ]
              }
            }
          ],
          "usageMetadata": {
            "totalTokenCount": 210
          }
        }
        """.data(using: .utf8))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))

        let step = try AgentGeminiClient.decodeStep(from: data, response: response, step: 2)

        XCTAssertEqual(step.summary, "Moving on")
        XCTAssertEqual(step.decision, .done)
        XCTAssertEqual(step.actions.count, 0)
    }

    func testDefaultAgentLLMClientUsesOpenAITransport() async throws {
        let transport = StubAgentLLMTransport(
            data: try XCTUnwrap("""
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"thinking\\":\\"Checking path\\",\\"summary\\":\\"Still going\\",\\"actions\\":[],\\"decision\\":\\"continue\\"}"
                  },
                  "finish_reason": "stop"
                }
              ]
            }
            """.data(using: .utf8)),
            response: try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions")),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
        )
        let client = DefaultAgentLLMClient(
            apiKey: "openai-key",
            model: "gpt-4.1",
            backend: .openAI,
            transport: transport
        )

        let step = try await client.nextStep(for: makeRequestContext())
        let request = await transport.lastRequest()

        XCTAssertEqual(step.summary, "Still going")
        XCTAssertEqual(step.decision, .continue)
        XCTAssertEqual(request?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer openai-key")
    }

    func testDefaultAgentLLMClientUsesGeminiTransport() async throws {
        let transport = StubAgentLLMTransport(
            data: try XCTUnwrap("""
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      {
                        "text": "{\\"thinking\\":\\"Opening found\\",\\"summary\\":\\"Done\\",\\"actions\\":[],\\"decision\\":\\"done\\"}"
                      }
                    ]
                  }
                }
              ]
            }
            """.data(using: .utf8)),
            response: try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
        )
        let client = DefaultAgentLLMClient(
            apiKey: "gemini-key",
            model: "gemini-2.5-flash",
            backend: .gemini,
            transport: transport
        )

        let step = try await client.nextStep(for: makeRequestContext())
        let request = await transport.lastRequest()

        XCTAssertEqual(step.summary, "Done")
        XCTAssertEqual(step.decision, .done)
        XCTAssertEqual(
            request?.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        )
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-key")
    }

    private func makeRequestContext() -> AgentLLMRequestContext {
        AgentLLMRequestContext(
            history: [],
            task: "Find the exit",
            step: 1,
            lastActionLog: "None",
            lastDepthText: "Clear path ahead: 120cm",
            lastPhoto: nil,
            navigationState: AgentNavigationState(),
            maxSteps: 20
        )
    }
}
