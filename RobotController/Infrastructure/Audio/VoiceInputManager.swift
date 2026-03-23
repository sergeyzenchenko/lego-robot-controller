import AVFoundation
import Speech

@available(iOS 26.0, *)
@MainActor
final class VoiceInputManager: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case error(String)
    }

    @Published var state: State = .idle
    @Published var transcript = ""

    private let service: any VoiceInputServicing
    private var session: (any VoiceInputSession)?
    private var setupTask: Task<Void, Never>?

    init(service: (any VoiceInputServicing)? = nil) {
        self.service = service ?? DefaultVoiceInputService()
    }

    func startListening() {
        guard state == .idle || isError else { return }
        state = .preparing
        transcript = ""
        AppLog.debug("[Voice] startListening")

        let service = self.service
        setupTask = Task { [weak self] in
            do {
                let session = try await service.startSession()
                AppLog.debug("[Voice] Setup complete, starting")

                await MainActor.run {
                    guard let self, self.state == .preparing else { return }
                    self.session = session
                    self.state = .listening
                    AppLog.debug("[Voice] State -> listening")
                }

                try await session.runTranscriptLoop { text in
                    await MainActor.run {
                        self?.transcript = text
                    }
                }

                await MainActor.run {
                    guard let self, self.session != nil else { return }
                    self.cleanup()
                    if self.state == .listening {
                        self.state = .idle
                    }
                }
            } catch is CancellationError {
                AppLog.debug("[Voice] Cancelled")
            } catch {
                AppLog.error("[Voice] Error: \(error)")
                await MainActor.run {
                    guard let self else { return }
                    self.cleanup()
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    func stopListening() {
        guard state == .listening || state == .preparing else { return }
        AppLog.debug("[Voice] stopListening")
        let session = self.session
        setupTask?.cancel()
        Task {
            await session?.stop()
        }
        cleanup()
        state = .idle
    }

    private var isError: Bool {
        if case .error = state { return true }
        return false
    }

    private func cleanup() {
        session = nil
        setupTask = nil
    }
}
