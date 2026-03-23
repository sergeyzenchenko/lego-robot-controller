import Foundation
import AVFoundation

enum RealtimePCM16 {
    static let sampleRate = 24_000
    static let channels = 1
    static let bitsPerSample = 16
    static let bytesPerSecond = 48_000
    static let outputChunkSizeBytes = 4_800

    static func wavData(
        from pcmData: Data,
        sampleRate: Int = sampleRate,
        channels: Int = channels,
        bitsPerSample: Int = bitsPerSample
    ) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = pcmData.count
        let chunkSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(chunkSize).littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        return header + pcmData
    }
}

@MainActor
final class RealtimeAudioSessionController {
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var audioTargetFormat: AVAudioFormat?
    private var audioOutputBuffer = Data()
    private var audioPlayer: AVAudioPlayer?
    private var totalAudioBytesReceived = 0
    private var audioPlaybackStartTime: Date?
    private var onInputAudioData: ((Data) -> Void)?
    private(set) var muted = false

    func configure(onInputAudioData: @escaping (Data) -> Void) throws {
        self.onInputAudioData = onInputAudioData

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(RealtimePCM16.sampleRate),
            channels: AVAudioChannelCount(RealtimePCM16.channels),
            interleaved: true
        ) else {
            throw LLMError.invalidResponse
        }

        audioTargetFormat = targetFormat
        startMicEngine()
    }

    func teardown() {
        pauseMicEngine()
        audioPlayer = nil
        audioOutputBuffer.removeAll()
        totalAudioBytesReceived = 0
        audioPlaybackStartTime = nil
        onInputAudioData = nil
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
    }

    func beginModelSpeech() {
        totalAudioBytesReceived = 0
        audioPlaybackStartTime = Date()
        pauseMicEngine()
    }

    func appendModelAudio(_ data: Data) {
        totalAudioBytesReceived += data.count
        playAudio(data)
    }

    func finishModelSpeech() async {
        flushAudioOutput()

        let audioDurationSec = Double(totalAudioBytesReceived) / Double(RealtimePCM16.bytesPerSecond)
        let elapsed = -(audioPlaybackStartTime ?? Date()).timeIntervalSinceNow
        let remainingPlayback = max(audioDurationSec - elapsed + 0.3, 0.3)

        AppLog.debug(
            "[Realtime] Audio done: \(String(format: "%.1f", audioDurationSec))s total, " +
            "\(String(format: "%.1f", elapsed))s elapsed, waiting \(String(format: "%.1f", remainingPlayback))s"
        )

        try? await Task.sleep(for: .seconds(remainingPlayback))

        totalAudioBytesReceived = 0
        audioPlaybackStartTime = nil
        resumeMicEngine()
    }

    private func startMicEngine() {
        guard audioEngine == nil, let targetFormat = audioTargetFormat else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else { return }
        audioConverter = converter

        inputNode.installTap(onBus: 0, bufferSize: 2_400, format: nil) { [weak self] buffer, _ in
            guard let self, !self.muted else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * Double(RealtimePCM16.sampleRate) / hwFormat.sampleRate
            )
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, converted.frameLength > 0 {
                self.sendAudioBuffer(converted)
            }
        }

        engine.prepare()
        try? engine.start()
        audioEngine = engine
        AppLog.debug("[Realtime] Mic engine started")
    }

    private func pauseMicEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        audioConverter = nil
        AppLog.debug("[Realtime] Mic engine paused")
    }

    private func resumeMicEngine() {
        guard audioEngine == nil, !muted else { return }
        startMicEngine()
    }

    private func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let int16Data = buffer.int16ChannelData else { return }
        let data = Data(bytes: int16Data[0], count: Int(buffer.frameLength) * 2)
        onInputAudioData?(data)
    }

    private func playAudio(_ data: Data) {
        audioOutputBuffer.append(data)

        guard audioOutputBuffer.count >= RealtimePCM16.outputChunkSizeBytes else { return }

        let chunk = audioOutputBuffer.prefix(RealtimePCM16.outputChunkSizeBytes)
        audioOutputBuffer.removeFirst(RealtimePCM16.outputChunkSizeBytes)

        do {
            let player = try AVAudioPlayer(data: RealtimePCM16.wavData(from: Data(chunk)))
            player.volume = 1.0
            player.play()
            audioPlayer = player
        } catch {
            AppLog.error("[Realtime] Play error: \(error)")
        }
    }

    private func flushAudioOutput() {
        guard !audioOutputBuffer.isEmpty else { return }

        do {
            let player = try AVAudioPlayer(data: RealtimePCM16.wavData(from: audioOutputBuffer))
            audioOutputBuffer.removeAll()
            player.play()
            audioPlayer = player
        } catch {
            AppLog.error("[Realtime] Flush play error: \(error)")
        }
    }
}
