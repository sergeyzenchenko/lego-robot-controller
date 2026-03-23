import SwiftUI

@available(iOS 26.0, *)
struct ChatView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @ObservedObject var robotViewModel: RobotViewModel
    @StateObject private var voiceInput: VoiceInputManager
    @State private var voiceMode = false
    @State private var silenceTask: Task<Void, Never>?

    private static let silenceDelay: Duration = .milliseconds(1500)

    init(
        chatViewModel: ChatViewModel,
        robotViewModel: RobotViewModel,
        makeVoiceInputManager: @escaping @MainActor () -> VoiceInputManager = { VoiceInputManager() }
    ) {
        self.chatViewModel = chatViewModel
        self.robotViewModel = robotViewModel
        _voiceInput = StateObject(wrappedValue: makeVoiceInputManager())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Voice mode banner
            if voiceMode && voiceInput.state == .listening {
                VoiceModeBanner(transcript: voiceInput.transcript)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !chatViewModel.isModelReady {
                            ModelLoadingView()
                        } else if chatViewModel.messages.isEmpty {
                            ChatEmptyState()
                        }

                        ForEach(chatViewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if chatViewModel.isResponding {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("typing")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: chatViewModel.messages.count) {
                    withAnimation {
                        if let last = chatViewModel.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: chatViewModel.isResponding) {
                    if chatViewModel.isResponding {
                        withAnimation {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            if !voiceMode {
                ChatInputBar(
                    text: $chatViewModel.inputText,
                    isResponding: chatViewModel.isResponding,
                    isConnected: robotViewModel.isConnected,
                    isModelReady: chatViewModel.isModelReady,
                    onSend: { chatViewModel.send() }
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleVoiceMode()
                } label: {
                    Image(systemName: voiceMode ? "waveform.circle.fill" : "waveform.circle")
                        .font(.title3)
                        .foregroundStyle(voiceMode ? .red : .blue)
                        .symbolEffect(.pulse, isActive: voiceMode && voiceInput.state == .listening)
                }
                .disabled(!robotViewModel.isConnected || !chatViewModel.isModelReady)
            }
        }
        .onAppear {
            chatViewModel.warmUp()
        }
        // Voice mode: auto-send on silence
        .onChange(of: voiceInput.transcript) {
            guard voiceMode else { return }
            let current = voiceInput.transcript
            guard !current.isEmpty else { return }

            // Reset silence timer on every transcript change
            silenceTask?.cancel()
            silenceTask = Task {
                try? await Task.sleep(for: Self.silenceDelay)
                guard !Task.isCancelled else { return }
                // Transcript hasn't changed → user stopped talking
                if voiceInput.transcript == current && !chatViewModel.isResponding {
                    AppLog.debug("[Voice] Silence detected, auto-sending: \(current)")
                    voiceInput.transcript = ""
                    chatViewModel.sendText(current)
                }
            }
        }
    }

    private func toggleVoiceMode() {
        voiceMode.toggle()
        if voiceMode {
            voiceInput.startListening()
        } else {
            silenceTask?.cancel()
            voiceInput.stopListening()
        }
    }
}
