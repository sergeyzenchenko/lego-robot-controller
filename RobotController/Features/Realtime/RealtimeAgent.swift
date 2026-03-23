import Foundation

// MARK: - Realtime Agent (WebSocket-based, zero dependencies)

@MainActor
final class RealtimeAgent: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isUserSpeaking = false
    @Published var isModelSpeaking = false
    @Published var muted = false
    @Published var error: String?

    private var webSocket: URLSessionWebSocketTask?
    private let audioSession = RealtimeAudioSessionController()
    private var robotViewModel: RobotViewModel?
    private var receiveTask: Task<Void, Never>?
    private var functionCallAccumulator = RealtimeFunctionCallAccumulator()

    func connect(apiKey: String, robotViewModel: RobotViewModel) {
        guard !apiKey.isEmpty else {
            error = "Set OpenAI API key in Chat settings"
            return
        }
        self.robotViewModel = robotViewModel
        error = nil
        isConnecting = true

        Task {
            do {
                try await setupAudio()
                try await connectWebSocket(apiKey: apiKey)
                isConnected = true
                isConnecting = false
                AppLog.debug("[Realtime] Connected")
            } catch {
                AppLog.error("[Realtime] Error: \(error)")
                self.error = error.localizedDescription
                isConnecting = false
            }
        }
    }

    func disconnect() {
        robotViewModel?.sendMotor(.stop)
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        audioSession.teardown()
        receiveTask?.cancel()
        isConnected = false
        isUserSpeaking = false
        isModelSpeaking = false
    }

    func toggleMute() {
        muted.toggle()
        audioSession.setMuted(muted)
    }

    // MARK: - WebSocket Connection

    private func connectWebSocket(apiKey: String) async throws {
        let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime-1.5")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: request)
        ws.resume()
        self.webSocket = ws

        try await sendJSON(
            RealtimeOutboundMessageBuilder.sessionUpdate(
                instructions: RealtimeAgentSupport.instructions,
                tools: RealtimeAgentSupport.toolDefinitions
            )
        )

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let ws = webSocket else { return }
        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let event = RealtimeServerEvent.parse(json: json) {
                        await handleEvent(event)
                    }
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let event = RealtimeServerEvent.parse(json: json) {
                        await handleEvent(event)
                    }
                @unknown default:
                    break
                }
            } catch {
                AppLog.error("[Realtime] Receive error: \(error)")
                isConnected = false
                self.error = "Disconnected"
                break
            }
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: RealtimeServerEvent) async {
        switch event {
        case .inputSpeechStarted:
            isUserSpeaking = true

        case .inputSpeechStopped:
            isUserSpeaking = false

        case .audioDelta(let audioData):
            let wasAlreadySpeaking = isModelSpeaking
            isModelSpeaking = true
            if !wasAlreadySpeaking {
                audioSession.beginModelSpeech()
                try? await sendJSON(RealtimeOutboundMessageBuilder.clearInputAudioBuffer())
            }
            audioSession.appendModelAudio(audioData)

        case .audioDone:
            await audioSession.finishModelSpeech()
            isModelSpeaking = false

        case .inputTranscript(let transcript):
            messages.append(AgentMessage(role: .user, text: transcript))

        case .outputTranscript(let transcript):
            messages.append(AgentMessage(role: .agent, text: transcript))

        case .functionCallDelta(let delta):
            functionCallAccumulator.apply(delta)

        case .functionCallDone(let completion):
            let pendingCall = functionCallAccumulator.complete(completion)
            appendToolMessage(pendingCall.name)

            let result = await RealtimeToolRunner.execute(
                name: pendingCall.name,
                arguments: pendingCall.arguments,
                robotViewModel: robotViewModel
            ) { [weak self] text in
                self?.appendToolMessage(text)
            }

            try? await sendJSON(
                RealtimeOutboundMessageBuilder.functionCallOutput(
                    callID: pendingCall.callID,
                    output: result.textResult
                )
            )

            if let photo = result.photoBase64 {
                try? await sendJSON(RealtimeOutboundMessageBuilder.inputImage(base64JPEG: photo))
            }

            try? await sendJSON(RealtimeOutboundMessageBuilder.createResponse())

        case .error(let msg):
            AppLog.error("[Realtime] Server error: \(msg)")
            messages.append(AgentMessage(role: .error, text: msg))
        }
    }

    private func setupAudio() async throws {
        try audioSession.configure { [weak self] pcmData in
            guard let self else { return }
            let base64 = pcmData.base64EncodedString()
            Task {
                try? await self.sendJSON(RealtimeOutboundMessageBuilder.appendInputAudio(base64Audio: base64))
            }
        }
    }

    private func appendToolMessage(_ text: String) {
        messages.append(AgentMessage(role: .tool, text: text))
    }

    // MARK: - Send JSON

    private func sendJSON(_ dict: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let string = String(data: data, encoding: .utf8)!
        try await webSocket?.send(.string(string))
    }
}
