import XCTest
@testable import RobotController

@MainActor
final class BLETransportTests: XCTestCase {

    func testConnectStartsScanWhenBluetoothReady() {
        let central = FakeBLECentralManager(state: .poweredOn)
        let transport = BLETransport(centralManager: central)
        let delegate = TransportDelegateSpy()
        transport.delegate = delegate

        transport.connect()

        XCTAssertEqual(central.scanCallCount, 1)
        XCTAssertEqual(delegate.phases.last, .scanning)
    }

    func testConnectPublishesUnavailableWhenBluetoothOff() {
        let central = FakeBLECentralManager(state: .poweredOff)
        let transport = BLETransport(centralManager: central)
        let delegate = TransportDelegateSpy()
        transport.delegate = delegate

        transport.connect()

        XCTAssertEqual(central.scanCallCount, 0)
        XCTAssertEqual(delegate.phases.last, .unavailable)
    }

    func testDiscoveredPeripheralPublishesConnectingAndRequestsConnect() {
        let central = FakeBLECentralManager(state: .poweredOn)
        let transport = BLETransport(centralManager: central)
        let delegate = TransportDelegateSpy()
        let peripheral = FakeBLEPeripheral(name: "XStRobot")
        transport.delegate = delegate

        transport.handleDiscoveredPeripheral(peripheral)

        XCTAssertEqual(central.stopScanCallCount, 1)
        XCTAssertEqual(central.connectedPeripherals.count, 1)
        XCTAssertTrue(peripheral.delegate === transport)
        XCTAssertEqual(delegate.phases.last, .connecting)
    }

    func testRequiresBothWritableCharacteristicsBeforeReady() {
        let central = FakeBLECentralManager(state: .poweredOn)
        let transport = BLETransport(centralManager: central)
        let delegate = TransportDelegateSpy()
        let peripheral = FakeBLEPeripheral(name: "XStRobot")
        let sensor = FakeBLECharacteristic(uuid: RobotUUID.sensor)
        let motors = FakeBLECharacteristic(uuid: RobotUUID.motors)
        let leds = FakeBLECharacteristic(uuid: RobotUUID.leds)
        transport.delegate = delegate

        transport.handleDiscoveredPeripheral(peripheral)
        transport.handleDiscoveredCharacteristics(on: peripheral, characteristics: [sensor, motors])
        XCTAssertNotEqual(delegate.phases.last, .ready)
        XCTAssertEqual(peripheral.notifyUUIDs, [RobotUUID.sensor])

        transport.handleDiscoveredCharacteristics(on: peripheral, characteristics: [leds])
        XCTAssertEqual(delegate.phases.last, .ready)
    }

    func testWritesUseReadyPeripheralCharacteristics() {
        let central = FakeBLECentralManager(state: .poweredOn)
        let transport = BLETransport(centralManager: central)
        let peripheral = FakeBLEPeripheral(name: "XStRobot")
        let motors = FakeBLECharacteristic(uuid: RobotUUID.motors)
        let leds = FakeBLECharacteristic(uuid: RobotUUID.leds)

        transport.handleDiscoveredPeripheral(peripheral)
        transport.handleDiscoveredCharacteristics(on: peripheral, characteristics: [motors, leds])
        transport.writeMotors(MotorCommand.forward.data)
        transport.writeLEDs(Data([0x03]))

        XCTAssertEqual(peripheral.writes.map(\.uuid), [RobotUUID.motors, RobotUUID.leds])
        XCTAssertEqual(peripheral.writes.map(\.data), [MotorCommand.forward.data, Data([0x03])])
    }

    func testIgnoresNonSelectedPeripheralWhenTargetIdentifierSet() {
        let central = FakeBLECentralManager(state: .poweredOn)
        let targetID = UUID()
        let transport = BLETransport(targetPeripheralIdentifier: targetID, centralManager: central)
        let delegate = TransportDelegateSpy()
        let wrongPeripheral = FakeBLEPeripheral(name: "XStRobot")
        transport.delegate = delegate

        transport.handleDiscoveredPeripheral(wrongPeripheral)

        XCTAssertEqual(central.connectedPeripherals.count, 0)
        XCTAssertTrue(delegate.phases.isEmpty)
    }
}
