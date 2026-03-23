import XCTest
@testable import RobotController

@MainActor
final class VoiceInputManagerTests: XCTestCase {

    @available(iOS 26.0, *)
    func testUsesInjectedServiceAndUpdatesTranscript() async {
        let session = StubVoiceInputSession(transcripts: ["hello", "hello robot"], waitsForStop: false)
        let service = StubVoiceInputService(session: session)
        let manager = VoiceInputManager(service: service)

        manager.startListening()
        await session.waitUntilStarted()
        await waitUntil { manager.state == .idle }

        let startCount = await service.startCount()
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(manager.transcript, "hello robot")
        XCTAssertEqual(manager.state, .idle)
    }

    @available(iOS 26.0, *)
    func testStopUsesInjectedSession() async {
        let session = StubVoiceInputSession(transcripts: [], waitsForStop: true)
        let service = StubVoiceInputService(session: session)
        let manager = VoiceInputManager(service: service)

        manager.startListening()
        await session.waitUntilStarted()
        await waitUntil { manager.state == .listening }

        XCTAssertEqual(manager.state, .listening)
        manager.stopListening()
        await session.waitUntilStopped()

        let stopCount = await session.stopCount()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(stopCount, 1)
    }

    @available(iOS 26.0, *)
    func testPublishesErrorFromService() async {
        let service = FailingVoiceInputService(message: "mic missing")
        let manager = VoiceInputManager(service: service)

        manager.startListening()
        await waitUntil {
            if case .error = manager.state {
                return true
            }
            return false
        }

        XCTAssertEqual(manager.state, .error("mic missing"))
    }
}
