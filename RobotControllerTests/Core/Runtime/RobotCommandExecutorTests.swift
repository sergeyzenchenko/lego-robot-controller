import XCTest
@testable import RobotController

@MainActor
final class RobotCommandExecutorTests: XCTestCase {

    func testMoveClampsDistanceTo35Centimeters() async {
        let driver = ExecutorTestDriver()
        let clock = RecordingClock()
        let executor = RobotCommandExecutor(
            driver: driver,
            perception: ExecutorTestPerception(),
            clock: clock
        )

        let result = await executor.execute(
            commands: [.move(direction: .forward, distanceCM: 100)],
            capturesFinalObservation: false
        )

        XCTAssertTrue(result.completed)
        XCTAssertEqual(driver.motorCommands.first, .forward)
        XCTAssertEqual(driver.motorCommands.last, .stop)
        XCTAssertEqual(driver.ledSnapshots, [])

        let sleeps = await clock.recordedSleeps()
        XCTAssertEqual(sleeps.count, 2)
        XCTAssertEqual(sleeps[0].totalMilliseconds, 10_000)
        XCTAssertEqual(sleeps[1].totalMilliseconds, 200)
    }

    func testCancellationStopsCurrentCommandAndSkipsLaterActions() async {
        let driver = ExecutorTestDriver()
        let clock = CancellationAwareClock()
        let executor = RobotCommandExecutor(
            driver: driver,
            perception: ExecutorTestPerception(),
            clock: clock
        )

        let task = Task {
            await executor.execute(
                commands: [
                    .move(direction: .forward, distanceCM: 20),
                    .setLEDs(LEDState(left: true, right: false))
                ],
                capturesFinalObservation: false
            )
        }

        await clock.waitUntilSleepStarts()
        task.cancel()

        let result = await task.value
        XCTAssertFalse(result.completed)
        XCTAssertEqual(driver.motorCommands.first, .forward)
        XCTAssertEqual(driver.motorCommands.last, .stop)
        XCTAssertTrue(driver.ledSnapshots.isEmpty)
    }

    func testDefaultRobotPerceptionProviderUsesInjectedAdapters() async throws {
        let photoCapture = StubPhotoCapture(data: Data([0x01, 0x02, 0x03]))
        let depthSensor = StubDepthSensor(payload: .unavailable)
        let provider = DefaultRobotPerceptionProvider(
            photoCapture: photoCapture,
            depthSensor: depthSensor
        )

        let photo = try await provider.capturePhoto()
        let depth = await provider.captureDepth()
        let photoCaptureCount = await photoCapture.captureCount()
        let depthCaptureCount = await depthSensor.captureCount()

        XCTAssertEqual(photo, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(depth.lidarAvailable, false)
        XCTAssertEqual(photoCaptureCount, 1)
        XCTAssertEqual(depthCaptureCount, 1)
    }
}
