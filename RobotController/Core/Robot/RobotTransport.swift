import Foundation

// MARK: - Transport Protocol

@MainActor
protocol RobotTransportDelegate: AnyObject {
    func transportDidChangePhase(_ phase: RobotConnectionPhase)
    func transportDidReceiveSensor(_ data: SensorData)
}

@MainActor
protocol RobotTransport: AnyObject {
    var delegate: RobotTransportDelegate? { get set }
    func connect()
    func disconnect()
    func writeMotors(_ data: Data)
    func writeLEDs(_ data: Data)
}

@MainActor
final class NoopRobotTransport: RobotTransport {
    weak var delegate: RobotTransportDelegate?

    func connect() {}

    func disconnect() {
        delegate?.transportDidChangePhase(.disconnected)
    }

    func writeMotors(_ data: Data) {}

    func writeLEDs(_ data: Data) {}
}
