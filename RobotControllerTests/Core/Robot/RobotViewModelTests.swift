import XCTest
@testable import RobotController

@MainActor
final class RobotViewModelTests: XCTestCase {

    private var transport: MockTransport!
    private var viewModel: RobotViewModel!

    override func setUp() {
        super.setUp()
        transport = MockTransport()
        viewModel = RobotViewModel(transport: transport)
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.connectionPhase, .idle)
        XCTAssertNil(viewModel.sensorData)
        XCTAssertEqual(viewModel.ledState, LEDState())
    }

    func testConnectCallsTransport() {
        viewModel.connect()
        XCTAssertEqual(transport.connectCallCount, 1)
    }

    func testDisconnectCallsTransport() {
        viewModel.disconnect()
        XCTAssertEqual(transport.disconnectCallCount, 1)
    }

    func testTransportStateChangeUpdatesViewModel() {
        transport.simulatePhase(.discovering)
        XCTAssertEqual(viewModel.connectionPhase, .discovering)
    }

    func testReadyPhaseMarksViewModelConnected() {
        transport.simulateConnected()
        XCTAssertEqual(viewModel.connectionPhase, .ready)
        XCTAssertTrue(viewModel.isConnected)
    }

    func testDisconnectResetsSensorAndLEDs() {
        transport.simulateConnected()
        transport.simulateSensor(SensorData(val1: 100, val2: 200, val3: 300))
        viewModel.toggleLeftLED()
        XCTAssertNotNil(viewModel.sensorData)
        XCTAssertTrue(viewModel.ledState.left)

        transport.simulateDisconnected()
        XCTAssertNil(viewModel.sensorData)
        XCTAssertEqual(viewModel.ledState, LEDState())
    }

    func testUnavailableResetsSensorAndLEDs() {
        transport.simulateConnected()
        transport.simulateSensor(SensorData(val1: 100, val2: 200, val3: 300))
        viewModel.toggleLeftLED()

        transport.simulatePhase(.unavailable)
        XCTAssertEqual(viewModel.connectionPhase, .unavailable)
        XCTAssertNil(viewModel.sensorData)
        XCTAssertEqual(viewModel.ledState, LEDState())
    }

    func testSendMotorForward() {
        viewModel.sendMotor(.forward)
        XCTAssertEqual(transport.motorWrites, [MotorCommand.forward.data])
    }

    func testSendMotorStop() {
        viewModel.sendMotor(.stop)
        XCTAssertEqual(transport.motorWrites, [MotorCommand.stop.data])
    }

    func testMultipleMotorCommands() {
        viewModel.sendMotor(.forward)
        viewModel.sendMotor(.spinLeft)
        viewModel.sendMotor(.stop)
        XCTAssertEqual(transport.motorWrites.count, 3)
    }

    func testToggleLeftLED() {
        viewModel.toggleLeftLED()
        XCTAssertTrue(viewModel.ledState.left)
        XCTAssertFalse(viewModel.ledState.right)
        XCTAssertEqual(transport.ledWrites.last, Data([0x01]))
    }

    func testToggleRightLED() {
        viewModel.toggleRightLED()
        XCTAssertFalse(viewModel.ledState.left)
        XCTAssertTrue(viewModel.ledState.right)
        XCTAssertEqual(transport.ledWrites.last, Data([0x02]))
    }

    func testToggleBothLEDs() {
        viewModel.toggleLeftLED()
        viewModel.toggleRightLED()
        XCTAssertEqual(transport.ledWrites.last, Data([0x03]))
    }

    func testToggleOffSendsZero() {
        viewModel.toggleLeftLED()
        viewModel.toggleLeftLED()
        XCTAssertEqual(transport.ledWrites.last, Data([0x00]))
    }

    func testLEDWriteCountMatchesToggleCount() {
        viewModel.toggleLeftLED()
        viewModel.toggleRightLED()
        viewModel.toggleLeftLED()
        XCTAssertEqual(transport.ledWrites.count, 3)
    }

    func testSensorDataUpdated() {
        let data = SensorData(val1: 3000, val2: 45, val3: 3550)
        transport.simulateSensor(data)
        XCTAssertEqual(viewModel.sensorData, data)
    }

    func testSensorDataUpdatesMultipleTimes() {
        transport.simulateSensor(SensorData(val1: 1, val2: 2, val3: 3))
        transport.simulateSensor(SensorData(val1: 10, val2: 20, val3: 30))
        XCTAssertEqual(viewModel.sensorData?.val1, 10)
    }

    func testTransportDelegateIsSet() {
        XCTAssertTrue(transport.delegate === viewModel.runtime)
    }
}
