import XCTest
@testable import RobotController

final class RobotConnectionStateMachineTests: XCTestCase {

    func testHappyPathReachesReady() {
        var machine = RobotConnectionStateMachine()

        XCTAssertEqual(machine.handle(.connectRequested), .scanning)
        XCTAssertEqual(machine.handle(.peripheralDiscovered), .connecting)
        XCTAssertEqual(machine.handle(.peripheralConnected), .discovering)
        XCTAssertEqual(machine.handle(.characteristicsReady), .ready)
    }

    func testDisconnectWithoutPeripheralGoesDirectlyDisconnected() {
        var machine = RobotConnectionStateMachine()

        XCTAssertEqual(machine.handle(.connectRequested), .scanning)
        XCTAssertEqual(machine.handle(.disconnectRequested(hasPeripheral: false)), .disconnected)
    }

    func testDisconnectWithPeripheralUsesDisconnectingPhase() {
        var machine = RobotConnectionStateMachine()

        XCTAssertEqual(machine.handle(.connectRequested), .scanning)
        XCTAssertEqual(machine.handle(.peripheralDiscovered), .connecting)
        XCTAssertEqual(machine.handle(.disconnectRequested(hasPeripheral: true)), .disconnecting)
        XCTAssertEqual(machine.handle(.peripheralDisconnected), .disconnected)
    }

    func testBluetoothUnavailableOverridesActiveConnection() {
        var machine = RobotConnectionStateMachine()

        XCTAssertEqual(machine.handle(.connectRequested), .scanning)
        XCTAssertEqual(machine.handle(.bluetoothUnavailable), .unavailable)
    }

    func testBluetoothReadyReturnsIdleWhenNotConnected() {
        var machine = RobotConnectionStateMachine()

        XCTAssertEqual(machine.handle(.bluetoothUnavailable), .unavailable)
        XCTAssertEqual(machine.handle(.bluetoothReady), .idle)
    }

    func testBluetoothReadyDoesNotDowngradeReadyPhase() {
        var machine = RobotConnectionStateMachine()

        XCTAssertEqual(machine.handle(.connectRequested), .scanning)
        XCTAssertEqual(machine.handle(.peripheralDiscovered), .connecting)
        XCTAssertEqual(machine.handle(.peripheralConnected), .discovering)
        XCTAssertEqual(machine.handle(.characteristicsReady), .ready)
        XCTAssertEqual(machine.handle(.bluetoothReady), .ready)
    }

    func testScanTimeoutEndsDisconnected() {
        var machine = RobotConnectionStateMachine()

        XCTAssertEqual(machine.handle(.connectRequested), .scanning)
        XCTAssertEqual(machine.handle(.scanTimedOut), .disconnected)
    }
}
