import Foundation

enum RobotConnectionEvent {
    case bluetoothReady
    case bluetoothUnavailable
    case connectRequested
    case scanTimedOut
    case peripheralDiscovered
    case peripheralConnected
    case characteristicsReady
    case disconnectRequested(hasPeripheral: Bool)
    case peripheralDisconnected
}

struct RobotConnectionStateMachine {
    private(set) var phase: RobotConnectionPhase = .idle

    @discardableResult
    mutating func handle(_ event: RobotConnectionEvent) -> RobotConnectionPhase {
        switch event {
        case .bluetoothReady:
            if phase != .ready {
                phase = .idle
            }
        case .bluetoothUnavailable:
            phase = .unavailable
        case .connectRequested:
            phase = .scanning
        case .scanTimedOut:
            phase = .disconnected
        case .peripheralDiscovered:
            phase = .connecting
        case .peripheralConnected:
            phase = .discovering
        case .characteristicsReady:
            phase = .ready
        case .disconnectRequested(let hasPeripheral):
            phase = hasPeripheral ? .disconnecting : .disconnected
        case .peripheralDisconnected:
            phase = .disconnected
        }

        return phase
    }
}
