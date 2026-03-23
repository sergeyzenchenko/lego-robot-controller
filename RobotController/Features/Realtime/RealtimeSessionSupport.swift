import Foundation

struct RealtimeFunctionCallDelta: Equatable {
    let callID: String
    let name: String?
    let argumentsDelta: String
}

struct RealtimeFunctionCallCompletion: Equatable {
    let callID: String
    let name: String?
}

struct RealtimePendingToolCall: Equatable {
    let callID: String
    let name: String
    let arguments: String
}

enum RealtimeServerEvent: Equatable {
    case inputSpeechStarted
    case inputSpeechStopped
    case audioDelta(Data)
    case audioDone
    case inputTranscript(String)
    case outputTranscript(String)
    case functionCallDelta(RealtimeFunctionCallDelta)
    case functionCallDone(RealtimeFunctionCallCompletion)
    case error(String)

    static func parse(json: [String: Any]) -> RealtimeServerEvent? {
        guard let type = json["type"] as? String else { return nil }

        switch type {
        case "input_audio_buffer.speech_started":
            return .inputSpeechStarted

        case "input_audio_buffer.speech_stopped":
            return .inputSpeechStopped

        case "response.audio.delta":
            guard let delta = json["delta"] as? String,
                  let audioData = Data(base64Encoded: delta) else { return nil }
            return .audioDelta(audioData)

        case "response.audio.done":
            return .audioDone

        case "conversation.item.input_audio_transcription.completed":
            guard let transcript = json["transcript"] as? String,
                  !transcript.isEmpty else { return nil }
            return .inputTranscript(transcript)

        case "response.audio_transcript.done":
            guard let transcript = json["transcript"] as? String,
                  !transcript.isEmpty else { return nil }
            return .outputTranscript(transcript)

        case "response.function_call_arguments.delta":
            return .functionCallDelta(
                RealtimeFunctionCallDelta(
                    callID: json["call_id"] as? String ?? "",
                    name: json["name"] as? String,
                    argumentsDelta: json["delta"] as? String ?? ""
                )
            )

        case "response.function_call_arguments.done":
            return .functionCallDone(
                RealtimeFunctionCallCompletion(
                    callID: json["call_id"] as? String ?? "",
                    name: json["name"] as? String
                )
            )

        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            return .error(message)

        default:
            return nil
        }
    }
}

struct RealtimeFunctionCallAccumulator {
    private var pendingArguments: [String: String] = [:]
    private var pendingNames: [String: String] = [:]

    mutating func apply(_ delta: RealtimeFunctionCallDelta) {
        pendingArguments[delta.callID, default: ""] += delta.argumentsDelta
        if let name = delta.name {
            pendingNames[delta.callID] = name
        }
    }

    mutating func complete(_ completion: RealtimeFunctionCallCompletion) -> RealtimePendingToolCall {
        let callID = completion.callID
        let name = completion.name ?? pendingNames[callID] ?? "unknown"
        let arguments = pendingArguments[callID] ?? "{}"

        pendingArguments.removeValue(forKey: callID)
        pendingNames.removeValue(forKey: callID)

        return RealtimePendingToolCall(callID: callID, name: name, arguments: arguments)
    }
}

enum RealtimeOutboundMessageBuilder {
    static func sessionUpdate(instructions: String, tools: [[String: Any]]) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "instructions": instructions,
                "voice": "shimmer",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "gpt-4o-mini-transcribe"],
                "turn_detection": ["type": "server_vad"],
                "tools": tools,
                "tool_choice": "auto",
                "modalities": ["text", "audio"]
            ] as [String: Any]
        ]
    }

    static func clearInputAudioBuffer() -> [String: Any] {
        ["type": "input_audio_buffer.clear"]
    }

    static func appendInputAudio(base64Audio: String) -> [String: Any] {
        [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]
    }

    static func functionCallOutput(callID: String, output: String) -> [String: Any] {
        [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callID,
                "output": output
            ] as [String: Any]
        ]
    }

    static func inputImage(base64JPEG: String) -> [String: Any] {
        [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_image",
                        "image_url": "data:image/jpeg;base64,\(base64JPEG)"
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ]
    }

    static func createResponse() -> [String: Any] {
        ["type": "response.create"]
    }
}
