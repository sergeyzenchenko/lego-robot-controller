import XCTest
@testable import RobotController

@MainActor
final class RobotRuntimeTests: XCTestCase {

    func testDisconnectCancelsCurrentOperationAndStopsRobot() async {
        let transport = MockTransport()
        let clock = RuntimeCancellationClock()
        let runtime = RobotRuntime(
            transport: transport,
            perception: RuntimeTestPerception(),
            clock: clock,
            speechSynthesizer: RuntimeSpeechSynthesizer()
        )

        let task = Task {
            await runtime.execute(
                commands: [
                    .move(direction: .forward, distanceCM: 20),
                    .setLEDs(LEDState(left: true, right: false))
                ],
                capturesFinalObservation: false
            )
        }

        await clock.waitUntilSleepStarts()
        runtime.disconnect()

        let result = await task.value
        XCTAssertFalse(result.completed)
        XCTAssertEqual(transport.disconnectCallCount, 1)
        XCTAssertTrue(transport.motorWrites.contains(MotorCommand.forward.data))
        XCTAssertEqual(transport.motorWrites.last, MotorCommand.stop.data)
        XCTAssertTrue(transport.ledWrites.isEmpty)
        XCTAssertEqual(runtime.operationStatus, .idle)
    }

    func testUnavailablePhaseCancelsCurrentOperationAndResetsState() async {
        let transport = MockTransport()
        let clock = RuntimeCancellationClock()
        let runtime = RobotRuntime(
            transport: transport,
            perception: RuntimeTestPerception(),
            clock: clock,
            speechSynthesizer: RuntimeSpeechSynthesizer()
        )

        runtime.setLEDState(LEDState(left: true, right: true))
        runtime.transportDidReceiveSensor(SensorData(val1: 1, val2: 2, val3: 3))

        let task = Task {
            await runtime.execute(
                commands: [.move(direction: .forward, distanceCM: 20)],
                capturesFinalObservation: false
            )
        }

        await clock.waitUntilSleepStarts()
        runtime.transportDidChangePhase(.unavailable)

        let result = await task.value
        XCTAssertFalse(result.completed)
        XCTAssertEqual(runtime.connectionPhase, .unavailable)
        XCTAssertEqual(runtime.operationStatus, .idle)
        XCTAssertNil(runtime.sensorData)
        XCTAssertEqual(runtime.ledState, LEDState())
        XCTAssertEqual(transport.motorWrites.last, MotorCommand.stop.data)
    }
}
