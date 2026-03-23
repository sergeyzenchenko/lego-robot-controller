import Foundation
@testable import RobotController

@MainActor
final class ExecutorTestDriver: RobotCommandDriving {
    var ledState = LEDState()
    var motorCommands: [MotorCommand] = []
    var ledSnapshots: [LEDState] = []

    func sendMotor(_ command: MotorCommand) {
        motorCommands.append(command)
    }

    func setLEDState(_ state: LEDState) {
        ledState = state
        ledSnapshots.append(state)
    }
}

struct ExecutorTestPerception: RobotPerceptionProviding {
    func capturePhoto() async throws -> Data {
        Data()
    }

    func captureDepth() async -> AgentDepthPayload {
        .unavailable
    }
}

actor StubPhotoCapture: RobotPhotoCapturing {
    let data: Data
    private var captures = 0

    init(data: Data) {
        self.data = data
    }

    func capturePhoto() async throws -> Data {
        captures += 1
        return data
    }

    func captureCount() -> Int {
        captures
    }
}

actor StubDepthSensor: RobotDepthSensing {
    let payload: AgentDepthPayload
    private var captures = 0

    init(payload: AgentDepthPayload) {
        self.payload = payload
    }

    func captureDepth() async -> AgentDepthPayload {
        captures += 1
        return payload
    }

    func captureCount() -> Int {
        captures
    }
}

actor RecordingClock: RobotClock {
    private var sleeps: [RecordedSleep] = []

    func sleep(for duration: Duration) async throws {
        sleeps.append(RecordedSleep(duration: duration))
    }

    func recordedSleeps() -> [RecordedSleep] {
        sleeps
    }
}

actor CancellationAwareClock: RobotClock {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        if !started {
            started = true
            let continuations = waiters
            waiters.removeAll()
            continuations.forEach { $0.resume() }
        }

        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(10))
        }

        throw CancellationError()
    }

    func waitUntilSleepStarts() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

struct RecordedSleep: Equatable {
    let seconds: Int64
    let attoseconds: Int64

    init(duration: Duration) {
        let components = duration.components
        seconds = components.seconds
        attoseconds = components.attoseconds
    }

    var totalMilliseconds: Int64 {
        seconds * 1_000 + attoseconds / 1_000_000_000_000_000
    }
}
