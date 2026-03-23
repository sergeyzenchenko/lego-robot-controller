import SwiftUI

struct TaskInputView: View {
    @Binding var taskInput: String
    let robotConnected: Bool
    let apiKeySet: Bool
    @ObservedObject var voiceInput: VoiceInputManager
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.blue.opacity(0.6))

            Text("Autonomous Agent")
                .font(.title2.weight(.semibold))

            Text("Give the robot a mission.\nIt will explore and act on its own.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                HStack {
                    TextField("e.g. Find the exit", text: $taskInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)

                    Button {
                        if voiceInput.state == .listening {
                            voiceInput.stopListening()
                        } else {
                            voiceInput.startListening()
                        }
                    } label: {
                        Image(systemName: voiceInput.state == .listening ? "mic.fill" : "mic")
                            .foregroundStyle(voiceInput.state == .listening ? .red : .blue)
                            .symbolEffect(.pulse, isActive: voiceInput.state == .listening)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SuggestionChip("Find the exit") { taskInput = "Find the exit in this room" }
                        SuggestionChip("Explore the room") { taskInput = "Explore this room and describe what you find" }
                        SuggestionChip("Go to the wall") { taskInput = "Drive forward until you reach a wall" }
                        SuggestionChip("Patrol") { taskInput = "Do a patrol around the room perimeter" }
                    }
                }

                Button(action: onStart) {
                    Text("Start Mission")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!robotConnected || !apiKeySet || taskInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)

            if !apiKeySet {
                Label("Set OpenAI API key in Chat settings", systemImage: "key")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
    }
}

private struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.blue.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct AgentRunView: View {
    @ObservedObject var agent: AutonomousAgent
    let robotConnected: Bool
    @Binding var userReply: String
    let onStop: () -> Void
    let onReply: () -> Void
    let onNewTask: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AgentStatusBar(agent: agent, onStop: onStop, onNewTask: onNewTask)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(agent.log) { entry in
                            AgentLogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: agent.log.count) {
                    if let last = agent.log.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if case .paused(let question) = agent.status {
                VStack(spacing: 8) {
                    Text(question)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)

                    HStack {
                        TextField("Your reply...", text: $userReply)
                            .textFieldStyle(.plain)

                        Button("Send", action: onReply)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(userReply.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
            }
        }
    }
}

private struct AgentStatusBar: View {
    @ObservedObject var agent: AutonomousAgent
    let onStop: () -> Void
    let onNewTask: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.headline)
                if agent.status == .running {
                    Text("Step \(agent.stepCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if agent.status == .running {
                Button("Stop", role: .destructive, action: onStop)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if isFinal {
                Button("New Task", action: onNewTask)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch agent.status {
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .paused:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        case .idle:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch agent.status {
        case .idle: "Ready"
        case .running: "Running..."
        case .paused: "Waiting for input"
        case .done(let summary): summary
        case .failed(let summary): summary
        }
    }

    private var isFinal: Bool {
        switch agent.status {
        case .done, .failed, .idle:
            return true
        case .running, .paused:
            return false
        }
    }
}

private struct AgentLogRow: View {
    let entry: AutonomousAgent.LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
                .frame(width: 16)
            Text(entry.text)
                .font(.caption)
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.type {
        case .thinking:
            Image(systemName: "brain").font(.caption2).foregroundStyle(.purple)
        case .action:
            Image(systemName: "play.fill").font(.caption2).foregroundStyle(.orange)
        case .observation:
            Image(systemName: "eye").font(.caption2).foregroundStyle(.blue)
        case .decision:
            Image(systemName: "arrow.triangle.branch").font(.caption2).foregroundStyle(.green)
        case .photo:
            Image(systemName: "camera").font(.caption2).foregroundStyle(.teal)
        case .error:
            Image(systemName: "exclamationmark.triangle").font(.caption2).foregroundStyle(.red)
        case .tts:
            Image(systemName: "speaker.wave.2").font(.caption2).foregroundStyle(.indigo)
        }
    }

    private var color: Color {
        switch entry.type {
        case .error:
            return .red
        case .tts:
            return .indigo
        default:
            return .primary
        }
    }
}
