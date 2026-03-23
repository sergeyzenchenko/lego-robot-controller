import SwiftUI

// MARK: - Connection Header

struct ConnectionHeader: View {
    @ObservedObject var viewModel: RobotViewModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("XStRobot")
                    .font(.headline)
                Text(viewModel.connectionPhase.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.connectionPhase.isReady {
                Button("Disconnect", role: .destructive) {
                    viewModel.disconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var statusColor: Color {
        switch viewModel.connectionPhase {
        case .ready:
            return .green
        case .scanning, .connecting, .discovering, .disconnecting:
            return .orange
        case .idle, .disconnected, .unavailable:
            return .red
        }
    }
}
