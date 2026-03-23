import SwiftUI

private struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ControlsHeaderView: View {
    let trackPhase: RobotConnectionPhase
    let handsPhase: RobotConnectionPhase
    let gamepadName: String?

    var body: some View {
        SectionCard(
            title: "Robot Controls",
            subtitle: "Assign one BLE controller to tracks and one to hands.",
            icon: "dot.radiowaves.left.and.right"
        ) {
            HStack(spacing: 12) {
                PhaseBadge(title: "Tracks", phase: trackPhase)
                PhaseBadge(title: "Hands", phase: handsPhase)
            }

            if let gamepadName {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundStyle(.green)
                    Text(gamepadName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("Left stick: tracks · Right stick: hands")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RobotAssignmentsView: View {
    @ObservedObject var coordinator: ControlsScreenCoordinator
    let trackPhase: RobotConnectionPhase
    let handsPhase: RobotConnectionPhase

    var body: some View {
        SectionCard(
            title: "Controller Assignment",
            subtitle: "Pick a discovered XStRobot for each role, then connect that slot.",
            icon: "sensor.tag.radiowaves.forward"
        ) {
            HStack {
                Text("\(coordinator.discoveredRobots.count) discovered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh", action: coordinator.refreshRobots)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            RobotRoleCard(
                role: .tracks,
                phase: trackPhase,
                selectionLabel: coordinator.selectionLabel(for: .tracks),
                options: coordinator.availableRobots(for: .tracks),
                selectAction: { coordinator.select($0, for: .tracks) },
                connectAction: { coordinator.connect(role: .tracks) },
                disconnectAction: { coordinator.disconnect(role: .tracks) }
            )

            RobotRoleCard(
                role: .hands,
                phase: handsPhase,
                selectionLabel: coordinator.selectionLabel(for: .hands),
                options: coordinator.availableRobots(for: .hands),
                selectAction: { coordinator.select($0, for: .hands) },
                connectAction: { coordinator.connect(role: .hands) },
                disconnectAction: { coordinator.disconnect(role: .hands) }
            )
        }
    }
}

private struct RobotRoleCard: View {
    let role: RobotControllerRole
    let phase: RobotConnectionPhase
    let selectionLabel: String
    let options: [RobotPeripheralDescriptor]
    let selectAction: (RobotPeripheralDescriptor?) -> Void
    let connectAction: () -> Void
    let disconnectAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(role.displayName, systemImage: role.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                StatusPill(phase: phase)
            }

            HStack(spacing: 12) {
                Menu {
                    Button("Unassigned") {
                        selectAction(nil)
                    }

                    if options.isEmpty {
                        Button("No controllers discovered") {}
                            .disabled(true)
                    } else {
                        ForEach(options) { option in
                            Button(option.displayName) {
                                selectAction(option)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectionLabel)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                if phase.isReady {
                    Button("Disconnect", role: .destructive, action: disconnectAction)
                        .buttonStyle(.bordered)
                } else {
                    Button("Connect", action: connectAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(selectionLabel == "Select controller" || phase.isBusy)
                }
            }

            Text(roleHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var roleHelpText: String {
        switch role {
        case .tracks:
            return "Tracks stay on the existing left-stick drive controls."
        case .hands:
            return "Hands map to the second motor pair and the DualShock right stick."
        }
    }
}

private struct PhaseBadge: View {
    let title: String
    let phase: RobotConnectionPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(phase.displayName)
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusColor: Color {
        switch phase {
        case .ready:
            return .green
        case .scanning, .connecting, .discovering, .disconnecting:
            return .orange
        case .idle, .disconnected, .unavailable:
            return .red
        }
    }
}

private struct StatusPill: View {
    let phase: RobotConnectionPhase

    var body: some View {
        Text(phase.displayName)
            .font(.caption.weight(.medium))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch phase {
        case .ready:
            return .green
        case .scanning, .connecting, .discovering, .disconnecting:
            return .orange
        case .idle, .disconnected, .unavailable:
            return .secondary
        }
    }
}

struct BluetoothUnavailableCard: View {
    var body: some View {
        SectionCard(
            title: "Bluetooth Unavailable",
            subtitle: "Enable Bluetooth access on the device to discover both robot controllers.",
            icon: "bolt.horizontal.circle"
        ) {
            Text("The assignment list only populates while CoreBluetooth is powered on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct TracksPanel: View {
    @ObservedObject var viewModel: RobotViewModel

    var body: some View {
        SectionCard(
            title: "Tracks",
            subtitle: "Manual drive controls plus the original LEDs and sensor feed.",
            icon: "figure.roll"
        ) {
            SensorStrip(sensorData: viewModel.sensorData)
            MotorPad(viewModel: viewModel)
            LEDRow(viewModel: viewModel)
        }
    }
}

struct HandsPanel: View {
    @ObservedObject var viewModel: RobotViewModel

    var body: some View {
        SectionCard(
            title: "Hands",
            subtitle: "Raise or lower both hands together. The DualShock right stick mirrors this motion.",
            icon: "hand.raised.fill"
        ) {
            HandMotorPad(viewModel: viewModel)
        }
    }
}

struct GamepadPanel: View {
    let controllerName: String
    let leftStick: (x: Float, y: Float)
    let rightStick: (x: Float, y: Float)

    var body: some View {
        SectionCard(
            title: "Gamepad",
            subtitle: "DualShock or other extended controller input.",
            icon: "gamecontroller.fill"
        ) {
            HStack {
                GamepadBadge(name: controllerName)
                Spacer()
            }
            GamepadStickView(
                leftLabel: "Tracks",
                rightLabel: "Hands",
                left: leftStick,
                right: rightStick
            )
        }
    }
}

struct ControlsEmptyState: View {
    var body: some View {
        SectionCard(
            title: "Waiting For Connections",
            subtitle: "Assign the track and hand controllers above, then connect whichever roles you need.",
            icon: "antenna.radiowaves.left.and.right"
        ) {
            Text("Once connected, this screen exposes separate panels for tracks and hands.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GamepadBadge: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gamecontroller.fill")
                .font(.caption2)
                .foregroundStyle(.green)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct GamepadStickView: View {
    let leftLabel: String
    let rightLabel: String
    let left: (x: Float, y: Float)
    let right: (x: Float, y: Float)

    var body: some View {
        HStack(spacing: 28) {
            StickCircle(label: leftLabel, x: left.x, y: left.y)
            StickCircle(label: rightLabel, x: right.x, y: right.y)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StickCircle: View {
    let label: String
    let x: Float
    let y: Float

    private let size: CGFloat = 116

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(.quaternary, lineWidth: 2)
                    .frame(width: size, height: size)

                Path { path in
                    path.move(to: CGPoint(x: size / 2, y: 8))
                    path.addLine(to: CGPoint(x: size / 2, y: size - 8))
                    path.move(to: CGPoint(x: 8, y: size / 2))
                    path.addLine(to: CGPoint(x: size - 8, y: size / 2))
                }
                .stroke(.quaternary, lineWidth: 1)

                Circle()
                    .fill(isActive ? .blue : .gray.opacity(0.4))
                    .frame(width: 24, height: 24)
                    .shadow(color: isActive ? .blue.opacity(0.5) : .clear, radius: 6)
                    .offset(
                        x: CGFloat(x) * (size / 2 - 12),
                        y: CGFloat(-y) * (size / 2 - 12)
                    )
                    .animation(.easeOut(duration: 0.05), value: x)
                    .animation(.easeOut(duration: 0.05), value: y)
            }
            .frame(width: size, height: size)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var isActive: Bool {
        abs(x) > 0.15 || abs(y) > 0.15
    }
}

struct SensorStrip: View {
    let sensorData: SensorData?

    var body: some View {
        HStack(spacing: 12) {
            if let sensorData {
                SensorPip(
                    icon: "battery.75percent",
                    value: "\(sensorData.val1)",
                    color: sensorData.val1 > 3000 ? .green : sensorData.val1 > 2900 ? .orange : .red
                )
                SensorPip(icon: "sensor", value: "\(sensorData.val2)", color: .blue)
                SensorPip(icon: "sensor", value: "\(sensorData.val3)", color: .cyan)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Waiting for sensors...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}

private struct SensorPip: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

struct LEDRow: View {
    @ObservedObject var viewModel: RobotViewModel

    var body: some View {
        HStack(spacing: 16) {
            LEDToggle(label: "Left Light", isOn: viewModel.ledState.left) {
                viewModel.toggleLeftLED()
            }
            LEDToggle(label: "Right Light", isOn: viewModel.ledState.right) {
                viewModel.toggleRightLED()
            }
        }
    }
}

private struct LEDToggle: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    if isOn {
                        Circle()
                            .fill(.green.opacity(0.3))
                            .frame(width: 28, height: 28)
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .shadow(color: .green.opacity(0.8), radius: 6)
                    } else {
                        Circle()
                            .fill(.gray.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Circle()
                            .fill(.gray.opacity(0.4))
                            .frame(width: 14, height: 14)
                    }
                }

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isOn ? AnyShapeStyle(.green.opacity(0.4)) : AnyShapeStyle(.quaternary),
                        lineWidth: 1.5
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                isOn
                                    ? AnyShapeStyle(.green.opacity(0.1))
                                    : AnyShapeStyle(Color(.secondarySystemGroupedBackground))
                            )
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

struct MotorPad: View {
    @ObservedObject var viewModel: RobotViewModel

    private let btnSize: CGFloat = 78

    var body: some View {
        VStack(spacing: 12) {
            DPadButton(symbol: "chevron.up", size: btnSize) {
                viewModel.sendMotor(.forward)
            } onRelease: {
                viewModel.sendMotor(.stop)
            }

            HStack(spacing: 16) {
                DPadButton(symbol: "arrow.counterclockwise", size: btnSize, tint: .orange) {
                    viewModel.sendMotor(.spinLeft)
                } onRelease: {
                    viewModel.sendMotor(.stop)
                }

                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(width: btnSize, height: btnSize)
                    Image(systemName: "circle.grid.cross")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }

                DPadButton(symbol: "arrow.clockwise", size: btnSize, tint: .orange) {
                    viewModel.sendMotor(.spinRight)
                } onRelease: {
                    viewModel.sendMotor(.stop)
                }
            }

            DPadButton(symbol: "chevron.down", size: btnSize) {
                viewModel.sendMotor(.backward)
            } onRelease: {
                viewModel.sendMotor(.stop)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct HandMotorPad: View {
    @ObservedObject var viewModel: RobotViewModel

    private let buttonSize: CGFloat = 86

    var body: some View {
        VStack(spacing: 12) {
            Text("Both Hands")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            DPadButton(symbol: "arrow.up", size: buttonSize, tint: .mint) {
                viewModel.sendMotor(.forward)
            } onRelease: {
                viewModel.sendMotor(.stop)
            }

            DPadButton(symbol: "arrow.down", size: buttonSize, tint: .pink) {
                viewModel.sendMotor(.backward)
            } onRelease: {
                viewModel.sendMotor(.stop)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DPadButton: View {
    let symbol: String
    let size: CGFloat
    var tint: Color = .blue
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.3, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isPressed
                                ? [tint.opacity(0.6), tint.opacity(0.5)]
                                : [tint, tint.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(
                        color: tint.opacity(isPressed ? 0.1 : 0.5),
                        radius: isPressed ? 2 : 10,
                        y: isPressed ? 1 : 5
                    )
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPress()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onRelease()
                    }
            )
    }
}
