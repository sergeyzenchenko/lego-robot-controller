import AVFoundation
import Speech

@available(iOS 26.0, *)
protocol VoiceInputServicing {
    func startSession() async throws -> any VoiceInputSession
}

@available(iOS 26.0, *)
protocol VoiceInputSession {
    func runTranscriptLoop(onTranscript: @escaping @Sendable (String) async -> Void) async throws
    func stop() async
}

@available(iOS 26.0, *)
struct DefaultVoiceInputService: VoiceInputServicing {
    func startSession() async throws -> any VoiceInputSession {
        SpeechFrameworkVoiceInputSession(components: try await VoiceSetup.prepare())
    }
}

@available(iOS 26.0, *)
private final class SpeechFrameworkVoiceInputSession: VoiceInputSession {
    private let components: VoiceSetup.Components

    init(components: VoiceSetup.Components) {
        self.components = components
    }

    func runTranscriptLoop(onTranscript: @escaping @Sendable (String) async -> Void) async throws {
        for try await result in components.transcriber.results {
            let text = String(result.text.characters)
            AppLog.debug("[Voice] Transcript: \(text) (final=\(result.isFinal))")
            if !text.isEmpty {
                await onTranscript(text)
            }
        }
        AppLog.debug("[Voice] Results stream ended")
    }

    func stop() async {
        components.continuation.finish()
        components.engine.stop()
        components.engine.inputNode.removeTap(onBus: 0)
        try? await components.analyzer.finalizeAndFinishThroughEndOfInput()
    }
}

// MARK: - Setup (entirely off main thread)

@available(iOS 26.0, *)
private enum VoiceSetup {

    struct Components {
        let transcriber: DictationTranscriber
        let analyzer: SpeechAnalyzer
        let engine: AVAudioEngine
        let continuation: AsyncStream<AnalyzerInput>.Continuation
    }

    static func prepare() async throws -> Components {
        AppLog.debug("[Voice:setup] 1. Audio session")
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        AppLog.debug("[Voice:setup] 2. Locale")
        let currentLocale = Locale.current
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: currentLocale) else {
            throw VoiceError.unsupportedLocale
        }
        AppLog.debug("[Voice:setup] Locale: \(supported.identifier)")

        AppLog.debug("[Voice:setup] 3. Reserve")
        try await AssetInventory.reserve(locale: supported)

        AppLog.debug("[Voice:setup] 4. Transcriber")
        let transcriber = DictationTranscriber(locale: supported, preset: .progressiveShortDictation)

        AppLog.debug("[Voice:setup] 5. Asset check")
        let status = await AssetInventory.status(forModules: [transcriber])
        AppLog.debug("[Voice:setup] Asset status: \(status)")

        if status == .supported {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                AppLog.debug("[Voice:setup] Downloading model...")
                try await request.downloadAndInstall()
                AppLog.debug("[Voice:setup] Downloaded")
            }
        } else if status == .unsupported {
            throw VoiceError.unsupportedLocale
        }

        AppLog.debug("[Voice:setup] 6. Audio engine")
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else { throw VoiceError.noMicrophone }
        AppLog.debug("[Voice:setup] HW format: \(hwFormat)")

        AppLog.debug("[Voice:setup] 7. Converter")
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw VoiceError.noMicrophone
        }
        AppLog.debug("[Voice:setup] Target format: \(targetFormat)")

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw VoiceError.formatConversion
        }

        AppLog.debug("[Voice:setup] 8. Analyzer")
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let analyzer = SpeechAnalyzer(
            inputSequence: stream,
            modules: [transcriber]
        )
        AppLog.debug("[Voice:setup] 9. prepareToAnalyze")
        try await analyzer.prepareToAnalyze(in: targetFormat)

        AppLog.debug("[Voice:setup] 10. Install tap + start")
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / hwFormat.sampleRate
            )
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil && converted.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }

        engine.prepare()
        try engine.start()
        AppLog.debug("[Voice:setup] Done")

        return Components(
            transcriber: transcriber,
            analyzer: analyzer,
            engine: engine,
            continuation: continuation
        )
    }
}

private enum VoiceError: LocalizedError {
    case unsupportedLocale
    case noMicrophone
    case formatConversion

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale: "Speech recognition not supported for current language"
        case .noMicrophone: "No microphone available"
        case .formatConversion: "Audio format conversion failed"
        }
    }
}
