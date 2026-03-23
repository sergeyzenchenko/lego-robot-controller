import XCTest
@testable import RobotController

final class RobotValueTypesTests: XCTestCase {

    func testSensorDataParsesLittleEndian() {
        let data = Data([0x02, 0x01, 0x04, 0x03, 0x06, 0x05])
        let sensor = SensorData(data: data)
        XCTAssertNotNil(sensor)
        XCTAssertEqual(sensor?.val1, 258)
        XCTAssertEqual(sensor?.val2, 772)
        XCTAssertEqual(sensor?.val3, 1286)
    }

    func testSensorDataRejectsShortData() {
        XCTAssertNil(SensorData(data: Data([0x01, 0x02, 0x03])))
        XCTAssertNil(SensorData(data: Data()))
    }

    func testSensorDataZeros() {
        let sensor = SensorData(data: Data([0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(sensor?.val1, 0)
        XCTAssertEqual(sensor?.val2, 0)
        XCTAssertEqual(sensor?.val3, 0)
    }

    func testSensorDataMaxValues() {
        let data = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        let sensor = SensorData(data: data)
        XCTAssertEqual(sensor?.val1, 65535)
        XCTAssertEqual(sensor?.val2, 65535)
        XCTAssertEqual(sensor?.val3, 65535)
    }

    func testSensorDataIgnoresExtraBytes() {
        let data = Data([0x10, 0x00, 0x20, 0x00, 0x30, 0x00, 0xFF, 0xFF])
        let sensor = SensorData(data: data)
        XCTAssertNotNil(sensor)
        XCTAssertEqual(sensor?.val1, 16)
        XCTAssertEqual(sensor?.val2, 32)
        XCTAssertEqual(sensor?.val3, 48)
    }

    func testMotorCommandForward() {
        XCTAssertEqual(MotorCommand.forward.data, Data([0x01, 0x80, 0x00, 0x01, 0x80, 0x00]))
    }

    func testMotorCommandBackward() {
        XCTAssertEqual(MotorCommand.backward.data, Data([0x02, 0x80, 0x00, 0x02, 0x80, 0x00]))
    }

    func testMotorCommandSpinLeft() {
        XCTAssertEqual(MotorCommand.spinLeft.data, Data([0x01, 0x80, 0x00, 0x02, 0x80, 0x00]))
    }

    func testMotorCommandSpinRight() {
        XCTAssertEqual(MotorCommand.spinRight.data, Data([0x02, 0x80, 0x00, 0x01, 0x80, 0x00]))
    }

    func testMotorCommandStop() {
        XCTAssertEqual(MotorCommand.stop.data, Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    }

    func testMotorCommandDataIsAlways6Bytes() {
        let commands: [MotorCommand] = [.forward, .backward, .spinLeft, .spinRight, .stop]
        for command in commands {
            XCTAssertEqual(command.data.count, 6)
        }
    }

    func testMotorCommandCustom() {
        let command = MotorCommand(
            leftDirection: .forward,
            leftSpeed: 0x40,
            rightDirection: .backward,
            rightSpeed: 0xFF
        )
        XCTAssertEqual(command.data, Data([0x01, 0x40, 0x00, 0x02, 0xFF, 0x00]))
    }

    func testLeftOnlyMotorCommandStopsRightMotor() {
        XCTAssertEqual(
            MotorCommand.leftOnly(.forward).data,
            Data([0x01, 0x80, 0x00, 0x00, 0x00, 0x00])
        )
    }

    func testRightOnlyMotorCommandStopsLeftMotor() {
        XCTAssertEqual(
            MotorCommand.rightOnly(.backward).data,
            Data([0x00, 0x00, 0x00, 0x02, 0x80, 0x00])
        )
    }

    func testLEDStateOff() {
        XCTAssertEqual(LEDState().byte, 0x00)
    }

    func testLEDStateLeft() {
        XCTAssertEqual(LEDState(left: true).byte, 0x01)
    }

    func testLEDStateRight() {
        XCTAssertEqual(LEDState(right: true).byte, 0x02)
    }

    func testLEDStateBoth() {
        XCTAssertEqual(LEDState(left: true, right: true).byte, 0x03)
    }

    func testLEDStateFromByte() {
        let state = LEDState(byte: 0x02)
        XCTAssertFalse(state.left)
        XCTAssertTrue(state.right)
    }

    func testLEDStateFromByteIgnoresHighBits() {
        let state = LEDState(byte: 0xFF)
        XCTAssertTrue(state.left)
        XCTAssertTrue(state.right)
    }

    func testLEDStateRoundTrip() {
        for byte: UInt8 in 0...3 {
            XCTAssertEqual(LEDState(byte: byte).byte, byte)
        }
    }
}
