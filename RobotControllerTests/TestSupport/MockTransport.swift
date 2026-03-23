import Foundation
@testable import RobotController

@MainActor
final class MockTransport: RobotTransport {
    weak var delegate: RobotTransportDelegate?

    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var motorWrites: [Data] = []
    private(set) var ledWrites: [Data] = []

    func connect() {
        connectCallCount += 1
    }

    func disconnect() {
        disconnectCallCount += 1
    }

    func writeMotors(_ data: Data) {
        motorWrites.append(data)
    }

    func writeLEDs(_ data: Data) {
        ledWrites.append(data)
    }

    func simulateConnected() {
        delegate?.transportDidChangePhase(.ready)
    }

    func simulateDisconnected() {
        delegate?.transportDidChangePhase(.disconnected)
    }

    func simulatePhase(_ phase: RobotConnectionPhase) {
        delegate?.transportDidChangePhase(phase)
    }

    func simulateSensor(_ data: SensorData) {
        delegate?.transportDidReceiveSensor(data)
    }
}
