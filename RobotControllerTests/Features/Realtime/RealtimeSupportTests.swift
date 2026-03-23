import XCTest
@testable import RobotController

final class RealtimeSupportTests: XCTestCase {

    func testRealtimePCM16WrapsPCMInWaveHeader() {
        let pcm = Data([0x01, 0x02, 0x03, 0x04])
        let wav = RealtimePCM16.wavData(from: pcm)

        XCTAssertEqual(wav.count, 44 + pcm.count)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(Data(wav.suffix(pcm.count)), pcm)
    }

    func testRealtimeServerEventParsesAudioDeltaAndTranscripts() {
        let audioJSON: [String: Any] = [
            "type": "response.audio.delta",
            "delta": Data([0x10, 0x20]).base64EncodedString()
        ]
        let inputTranscriptJSON: [String: Any] = [
            "type": "conversation.item.input_audio_transcription.completed",
            "transcript": "hello robot"
        ]
        let outputTranscriptJSON: [String: Any] = [
            "type": "response.audio_transcript.done",
            "transcript": "hello human"
        ]

        XCTAssertEqual(RealtimeServerEvent.parse(json: audioJSON), .audioDelta(Data([0x10, 0x20])))
        XCTAssertEqual(RealtimeServerEvent.parse(json: inputTranscriptJSON), .inputTranscript("hello robot"))
        XCTAssertEqual(RealtimeServerEvent.parse(json: outputTranscriptJSON), .outputTranscript("hello human"))
    }

    func testRealtimeFunctionCallAccumulatorCombinesDeltasAndCompletion() {
        var accumulator = RealtimeFunctionCallAccumulator()

        accumulator.apply(RealtimeFunctionCallDelta(callID: "call-1", name: "act", argumentsDelta: "{\"reason"))
        accumulator.apply(RealtimeFunctionCallDelta(callID: "call-1", name: nil, argumentsDelta: "ing\":\"go\"}"))

        let pending = accumulator.complete(RealtimeFunctionCallCompletion(callID: "call-1", name: nil))

        XCTAssertEqual(
            pending,
            RealtimePendingToolCall(callID: "call-1", name: "act", arguments: "{\"reasoning\":\"go\"}")
        )
    }

    func testRealtimeOutboundMessageBuilderCreatesFunctionCallOutputAndImageMessages() {
        let output = RealtimeOutboundMessageBuilder.functionCallOutput(callID: "call-7", output: "done")
        let image = RealtimeOutboundMessageBuilder.inputImage(base64JPEG: "abc123")

        XCTAssertEqual(output["type"] as? String, "conversation.item.create")
        let outputItem = output["item"] as? [String: Any]
        XCTAssertEqual(outputItem?["type"] as? String, "function_call_output")
        XCTAssertEqual(outputItem?["call_id"] as? String, "call-7")
        XCTAssertEqual(outputItem?["output"] as? String, "done")

        XCTAssertEqual(image["type"] as? String, "conversation.item.create")
        let imageItem = image["item"] as? [String: Any]
        XCTAssertEqual(imageItem?["type"] as? String, "message")
        let content = imageItem?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "input_image")
        XCTAssertEqual(content?.first?["image_url"] as? String, "data:image/jpeg;base64,abc123")
    }

    func testRealtimeToolResponseBuilderFormatsActAndLookResponses() {
        let result = RobotExecutionResult(
            log: ["move forward 10cm", "turn right 90deg"],
            photoBase64: "photo",
            depthPayload: .unavailable,
            depthText: "LiDAR depth data:\nNearest obstacle: 40cm (center)",
            lookPhotos: [],
            completed: true
        )

        let actText = RealtimeToolResponseBuilder.actResponse(actionCount: 2, result: result)
        let lookText = RealtimeToolResponseBuilder.lookResponse(depthText: "LiDAR depth: unavailable on this device.")

        XCTAssertTrue(actText.contains("Executed 2 actions: move forward 10cm. turn right 90deg."))
        XCTAssertTrue(actText.contains("LiDAR depth data:\nNearest obstacle: 40cm (center)"))
        XCTAssertTrue(lookText.contains("Photo taken without moving."))
        XCTAssertTrue(lookText.contains("LiDAR depth: unavailable on this device."))
    }

    func testRealtimeToolResponseBuilderFormatsDepthAvailabilityAndProgress() {
        let available = AgentDepthPayload(
            grid5x5: [],
            nearestObstacleCM: 22,
            nearestObstacleDirection: "left",
            clearPathAheadCM: 81,
            lidarAvailable: true
        )
        let unavailable = AgentDepthPayload.unavailable

        XCTAssertTrue(RealtimeToolResponseBuilder.depthText(from: available).hasPrefix("LiDAR depth data:\n"))
        XCTAssertEqual(
            RealtimeToolResponseBuilder.depthProgressMessage(from: available),
            "📐 Depth: nearest 22cm left, clear 81cm"
        )
        XCTAssertEqual(RealtimeToolResponseBuilder.depthText(from: unavailable), "LiDAR depth: unavailable on this device.")
        XCTAssertNil(RealtimeToolResponseBuilder.depthProgressMessage(from: unavailable))
    }
}
