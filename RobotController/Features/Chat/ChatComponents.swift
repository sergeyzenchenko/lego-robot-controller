import SwiftUI

struct VoiceModeBanner: View {
    let transcript: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)

            if transcript.isEmpty {
                Text("Listening...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(transcript)
                    .font(.subheadline)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.red.opacity(0.08))
    }
}

struct ModelLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 60)

            ProgressView()
                .controlSize(.large)

            Text("Loading model...")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Preparing on-device AI")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct ChatEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 60)

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Chat with your robot")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("\"Drive in a square\"")
                Text("\"Turn on lights and spin around\"")
                Text("\"Go forward 3 seconds then come back\"")
            }
            .font(.subheadline)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            UserBubble(text: message.text)
        case .reasoning:
            ReasoningBubble(text: message.text)
        case .action:
            ActionBubble(text: message.text)
        case .stats:
            StatsBubble(text: message.text)
        case .error:
            ErrorBubble(text: message.text)
        }
    }
}

private struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.blue, in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(.horizontal)
    }
}

private struct ErrorBubble: View {
    let text: String

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(text)
                    .foregroundStyle(.red)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 40)
        }
        .padding(.horizontal)
    }
}

private struct ReasoningBubble: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                        Text("Reasoning")
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 40)
        }
        .padding(.horizontal)
    }
}

private struct ActionBubble: View {
    let text: String

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
            )
            Spacer(minLength: 40)
        }
        .padding(.horizontal)
    }
}

private struct StatsBubble: View {
    let text: String

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "gauge.medium")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(text)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 7, height: 7)
                    .offset(y: sin((phase + Double(index) * 0.8)) * 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

@available(iOS 26.0, *)
struct ChatInputBar: View {
    @Binding var text: String
    let isResponding: Bool
    let isConnected: Bool
    let isModelReady: Bool
    let onSend: () -> Void

    private var placeholder: String {
        if !isModelReady { return "Loading model..." }
        if !isConnected { return "Connect robot first..." }
        return "Tell the robot what to do..."
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .disabled(!isConnected || !isModelReady)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? .blue : .gray.opacity(0.4))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        isConnected && isModelReady && !isResponding
            && !text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
