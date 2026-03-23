import AVFoundation
import Foundation

protocol TTSAudioTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionTTSAudioTransport: TTSAudioTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

protocol TTSAudioGenerating {
    func generateSpeechAudio(text: String, apiKey: String, voice: String) async throws -> Data
}

struct OpenAITTSAudioClient: TTSAudioGenerating {
    private let model: String
    private let transport: any TTSAudioTransport

    init(
        model: String = "tts-1",
        transport: any TTSAudioTransport = URLSessionTTSAudioTransport()
    ) {
        self.model = model
        self.transport = transport
    }

    func generateSpeechAudio(text: String, apiKey: String, voice: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": text,
            "voice": voice,
            "response_format": "mp3"
        ])

        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            AppLog.error("[TTS] API error: \(String(data: data, encoding: .utf8) ?? "")")
            throw LLMError.apiErrorDetail((response as? HTTPURLResponse)?.statusCode ?? 0, String(data: data, encoding: .utf8) ?? "")
        }

        return data
    }
}

@MainActor
protocol TTSAudioPlaying: AnyObject {
    func play(_ data: Data) async throws
}

@MainActor
final class AVAudioPlayerTTSAudioPlayer: TTSAudioPlaying {
    private var player: AVAudioPlayer?

    func play(_ data: Data) async throws {
        let player = try AVAudioPlayer(data: data)
        self.player = player
        player.play()

        while player.isPlaying {
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
