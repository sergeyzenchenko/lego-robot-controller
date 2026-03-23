import XCTest
@testable import RobotController

@MainActor
final class TTSTests: XCTestCase {

    func testOpenAITTSAudioClientUsesTransportAndReturnsAudioData() async throws {
        let transport = StubTTSAudioTransport(
            data: Data([0x10, 0x20, 0x30]),
            response: try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(URL(string: "https://api.openai.com/v1/audio/speech")),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
        )
        let client = OpenAITTSAudioClient(transport: transport)

        let audioData = try await client.generateSpeechAudio(text: "Status update", apiKey: "tts-key", voice: "nova")
        let request = await transport.lastRequest()
        let body = try XCTUnwrap(request?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(audioData, Data([0x10, 0x20, 0x30]))
        XCTAssertEqual(request?.url?.absoluteString, "https://api.openai.com/v1/audio/speech")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer tts-key")
        XCTAssertEqual(json["model"] as? String, "tts-1")
        XCTAssertEqual(json["input"] as? String, "Status update")
        XCTAssertEqual(json["voice"] as? String, "nova")
    }

    func testTTSManagerUsesInjectedAudioClientAndPlayer() async {
        let audioClient = StubTTSAudioClient(data: Data([0xAA, 0xBB]))
        let audioPlayer = StubTTSAudioPlayer()
        let manager = TTSManager(audioClient: audioClient, audioPlayer: audioPlayer)

        await manager.speak("Obstacle ahead", apiKey: "tts-key", voice: "alloy")

        let requests = await audioClient.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.text, "Obstacle ahead")
        XCTAssertEqual(requests.first?.apiKey, "tts-key")
        XCTAssertEqual(requests.first?.voice, "alloy")
        XCTAssertEqual(audioPlayer.playedData, [Data([0xAA, 0xBB])])
    }

    func testDefaultRobotSpeechSynthesizerUsesInjectedTTSManager() async {
        let manager = StubTTSManager()
        let synthesizer = DefaultRobotSpeechSynthesizer(tts: manager)

        await synthesizer.speak("Step complete", apiKey: "openai-key", voice: "ash")

        XCTAssertEqual(
            manager.calls,
            [StubTTSManager.Call(text: "Step complete", apiKey: "openai-key", voice: "ash")]
        )
    }
}
