import Foundation
@testable import RobotController

actor StubTTSAudioTransport: TTSAudioTransport {
    private(set) var request: URLRequest?
    let dataResponse: Data
    let urlResponse: URLResponse

    init(data: Data, response: URLResponse) {
        dataResponse = data
        urlResponse = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (dataResponse, urlResponse)
    }

    func lastRequest() -> URLRequest? {
        request
    }
}

actor StubTTSAudioClient: TTSAudioGenerating {
    struct Request: Equatable {
        let text: String
        let apiKey: String
        let voice: String
    }

    let data: Data
    private var recordedRequests: [Request] = []

    init(data: Data) {
        self.data = data
    }

    func generateSpeechAudio(text: String, apiKey: String, voice: String) async throws -> Data {
        recordedRequests.append(Request(text: text, apiKey: apiKey, voice: voice))
        return data
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

@MainActor
final class StubTTSAudioPlayer: TTSAudioPlaying {
    var playedData: [Data] = []

    func play(_ data: Data) async throws {
        playedData.append(data)
    }
}

@MainActor
final class StubTTSManager: TTSManaging {
    struct Call: Equatable {
        let text: String
        let apiKey: String
        let voice: String
    }

    var calls: [Call] = []

    func speak(_ text: String, apiKey: String, voice: String) async {
        calls.append(Call(text: text, apiKey: apiKey, voice: voice))
    }
}

@available(iOS 26.0, *)
actor StubVoiceInputService: VoiceInputServicing {
    private let session: any VoiceInputSession
    private var starts = 0

    init(session: any VoiceInputSession) {
        self.session = session
    }

    func startSession() async throws -> any VoiceInputSession {
        starts += 1
        return session
    }

    func startCount() -> Int {
        starts
    }
}

@available(iOS 26.0, *)
actor StubVoiceInputSession: VoiceInputSession {
    private let transcripts: [String]
    private let waitsForStop: Bool
    private var started = false
    private var stops = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    init(transcripts: [String], waitsForStop: Bool) {
        self.transcripts = transcripts
        self.waitsForStop = waitsForStop
    }

    func runTranscriptLoop(onTranscript: @escaping @Sendable (String) async -> Void) async throws {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        for transcript in transcripts {
            await onTranscript(transcript)
        }

        while waitsForStop && stops == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func stop() async {
        stops += 1
        let waiters = stopWaiters
        stopWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilStopped() async {
        guard stops == 0 else { return }
        await withCheckedContinuation { continuation in
            stopWaiters.append(continuation)
        }
    }

    func stopCount() -> Int {
        stops
    }
}

@available(iOS 26.0, *)
actor FailingVoiceInputService: VoiceInputServicing {
    let message: String

    init(message: String) {
        self.message = message
    }

    func startSession() async throws -> any VoiceInputSession {
        throw NSError(domain: "VoiceInputTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
