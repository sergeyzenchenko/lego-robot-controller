import Foundation

// MARK: - TTS via OpenAI API

@MainActor
protocol TTSManaging: AnyObject {
    func speak(_ text: String, apiKey: String, voice: String) async
}

@MainActor
final class TTSManager: TTSManaging {
    private let audioClient: any TTSAudioGenerating
    private let audioPlayer: any TTSAudioPlaying

    init(
        audioClient: (any TTSAudioGenerating)? = nil,
        audioPlayer: (any TTSAudioPlaying)? = nil
    ) {
        self.audioClient = audioClient ?? OpenAITTSAudioClient()
        self.audioPlayer = audioPlayer ?? AVAudioPlayerTTSAudioPlayer()
    }

    func speak(_ text: String, apiKey: String, voice: String = "shimmer") async {
        guard !text.isEmpty, !apiKey.isEmpty else { return }

        do {
            let audioData = try await audioClient.generateSpeechAudio(text: text, apiKey: apiKey, voice: voice)
            try await audioPlayer.play(audioData)
        } catch {
            AppLog.error("[TTS] Error: \(error)")
        }
    }
}
