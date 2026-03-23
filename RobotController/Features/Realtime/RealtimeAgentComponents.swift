import SwiftUI

struct AgentEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 60)
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Voice Agent")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Talk directly to the AI.\nIt hears you, speaks back, and controls the robot.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct AgentBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            bubbleContent

            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.blue, in: RoundedRectangle(cornerRadius: 18))
        case .agent:
            Text(message.text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        case .tool:
            HStack(spacing: 6) {
                Image(systemName: "wrench.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text(message.text)
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.purple.opacity(0.1), in: Capsule())
        case .error:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message.text)
                    .foregroundStyle(.red)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct AgentBottomBar: View {
    @ObservedObject var agent: RealtimeAgent
    let isRobotConnected: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onToggleMute: () -> Void

    private var micIcon: String {
        if agent.muted { return "mic.slash.fill" }
        if agent.isModelSpeaking { return "mic.slash" }
        if agent.isUserSpeaking { return "mic.fill" }
        return "mic"
    }

    private var micColor: Color {
        if agent.muted { return .red }
        if agent.isModelSpeaking { return .orange }
        if agent.isUserSpeaking { return .green }
        return .secondary
    }

    private var micLabel: String {
        if agent.isModelSpeaking { return "Muted" }
        return "You"
    }

    var body: some View {
        VStack(spacing: 8) {
            if let error = agent.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if agent.isConnected {
                connectedControls
            } else {
                connectButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var connectedControls: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Image(systemName: micIcon)
                    .foregroundStyle(micColor)
                    .symbolEffect(.pulse, isActive: agent.isUserSpeaking)
                Text(micLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(action: onToggleMute) {
                Image(systemName: buttonMicIcon)
                    .font(.title2)
                    .foregroundStyle(buttonMicColor)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(buttonMicColor.opacity(0.15)))
            }
            .disabled(agent.isModelSpeaking)

            VStack(spacing: 4) {
                Image(systemName: agent.isModelSpeaking ? "speaker.wave.3.fill" : "speaker.fill")
                    .foregroundStyle(agent.isModelSpeaking ? .green : .secondary)
                    .symbolEffect(.pulse, isActive: agent.isModelSpeaking)
                Text("Agent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("End", role: .destructive, action: onDisconnect)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var connectButton: some View {
        Button(action: onConnect) {
            HStack(spacing: 8) {
                if agent.isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(agent.isConnecting ? "Connecting..." : "Start Voice Agent")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isRobotConnected || agent.isConnecting)
    }

    private var buttonMicIcon: String {
        if agent.muted { return "mic.slash.fill" }
        if agent.isModelSpeaking { return "mic.slash" }
        return "mic.fill"
    }

    private var buttonMicColor: Color {
        if agent.muted { return .red }
        if agent.isModelSpeaking { return .orange }
        return .blue
    }
}
