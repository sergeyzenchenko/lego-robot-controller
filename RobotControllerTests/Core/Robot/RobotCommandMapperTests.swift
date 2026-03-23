import XCTest
@testable import RobotController

final class RobotCommandMapperTests: XCTestCase {

    func testRobotCommandMapperClampsMoveDurationIntoDistanceRange() {
        let command = RobotCommandMapper.command(for: .moveForward(MoveParams(duration: 20)))

        guard case .move(let direction, let distanceCM) = command else {
            return XCTFail("Expected move command")
        }

        XCTAssertEqual(direction, .forward)
        XCTAssertEqual(distanceCM, 35)
    }

    func testRobotCommandMapperConvertsSpinAndLEDActions() {
        let spin = RobotCommandMapper.command(for: .spin360)
        let leds = RobotCommandMapper.command(for: .setLEDs(LEDParams(leftOn: true, rightOn: false)))

        guard case .turn(let direction, let degrees) = spin else {
            return XCTFail("Expected turn command")
        }
        guard case .setLEDs(let state) = leds else {
            return XCTFail("Expected LED command")
        }

        XCTAssertEqual(direction, .left)
        XCTAssertEqual(degrees, 358)
        XCTAssertEqual(state, LEDState(left: true, right: false))
    }

    func testAgentCommandMapperUpdatesLEDStateAcrossActions() {
        let actions = [
            AgentAction(type: .led, direction: nil, distance_cm: nil, degrees: nil, status: .on, led: .left, seconds: nil),
            AgentAction(type: .led, direction: nil, distance_cm: nil, degrees: nil, status: .on, led: .right, seconds: nil),
            AgentAction(type: .led, direction: nil, distance_cm: nil, degrees: nil, status: .off, led: .left, seconds: nil)
        ]

        let commands = AgentCommandMapper.commands(for: actions, initialLEDState: LEDState())

        guard commands.count == 3 else {
            return XCTFail("Expected three commands")
        }

        guard case .setLEDs(let first) = commands[0],
              case .setLEDs(let second) = commands[1],
              case .setLEDs(let third) = commands[2] else {
            return XCTFail("Expected LED commands")
        }

        XCTAssertEqual(first, LEDState(left: true, right: false))
        XCTAssertEqual(second, LEDState(left: true, right: true))
        XCTAssertEqual(third, LEDState(left: false, right: true))
    }

    func testAgentCommandMapperUsesDefaultsForMoveTurnAndWait() {
        let move = AgentCommandMapper.command(
            for: AgentAction(type: .move, direction: nil, distance_cm: nil, degrees: nil, status: nil, led: nil, seconds: nil),
            currentLEDState: LEDState()
        )
        let turn = AgentCommandMapper.command(
            for: AgentAction(type: .turn, direction: nil, distance_cm: nil, degrees: nil, status: nil, led: nil, seconds: nil),
            currentLEDState: LEDState()
        )
        let wait = AgentCommandMapper.command(
            for: AgentAction(type: .wait, direction: nil, distance_cm: nil, degrees: nil, status: nil, led: nil, seconds: nil),
            currentLEDState: LEDState()
        )

        guard case .move(let moveDirection, let distanceCM) = move else {
            return XCTFail("Expected move command")
        }
        guard case .turn(let turnDirection, let degrees) = turn else {
            return XCTFail("Expected turn command")
        }
        guard case .wait(let seconds) = wait else {
            return XCTFail("Expected wait command")
        }

        XCTAssertEqual(moveDirection, .forward)
        XCTAssertEqual(distanceCM, 10)
        XCTAssertEqual(turnDirection, .right)
        XCTAssertEqual(degrees, 90)
        XCTAssertEqual(seconds, 1)
    }

    func testRealtimeToolActionMapperUpdatesLEDStateAcrossActions() {
        let actions = [
            RealtimeToolAction(type: .led, direction: nil, distance_cm: nil, degrees: nil, status: .on, led: .left, seconds: nil),
            RealtimeToolAction(type: .led, direction: nil, distance_cm: nil, degrees: nil, status: .on, led: .right, seconds: nil),
            RealtimeToolAction(type: .led, direction: nil, distance_cm: nil, degrees: nil, status: .off, led: .left, seconds: nil)
        ]

        let commands = actions.robotCommands(initialLEDState: LEDState())

        guard commands.count == 3 else {
            return XCTFail("Expected three commands")
        }

        guard case .setLEDs(let first) = commands[0],
              case .setLEDs(let second) = commands[1],
              case .setLEDs(let third) = commands[2] else {
            return XCTFail("Expected LED commands")
        }

        XCTAssertEqual(first, LEDState(left: true, right: false))
        XCTAssertEqual(second, LEDState(left: true, right: true))
        XCTAssertEqual(third, LEDState(left: false, right: true))
    }

    func testRealtimeToolActionMapperUsesDefaultsForMoveTurnDelayAndStop() {
        let commands = [
            RealtimeToolAction(type: .move, direction: nil, distance_cm: nil, degrees: nil, status: nil, led: nil, seconds: nil),
            RealtimeToolAction(type: .turn, direction: nil, distance_cm: nil, degrees: nil, status: nil, led: nil, seconds: nil),
            RealtimeToolAction(type: .delay, direction: nil, distance_cm: nil, degrees: nil, status: nil, led: nil, seconds: nil),
            RealtimeToolAction(type: .stop, direction: nil, distance_cm: nil, degrees: nil, status: nil, led: nil, seconds: nil)
        ].robotCommands(initialLEDState: LEDState())

        guard commands.count == 4 else {
            return XCTFail("Expected four commands")
        }

        guard case .move(let moveDirection, let distanceCM) = commands[0] else {
            return XCTFail("Expected move command")
        }
        guard case .turn(let turnDirection, let degrees) = commands[1] else {
            return XCTFail("Expected turn command")
        }
        guard case .wait(let seconds) = commands[2] else {
            return XCTFail("Expected wait command")
        }
        guard case .stop = commands[3] else {
            return XCTFail("Expected stop command")
        }

        XCTAssertEqual(moveDirection, .forward)
        XCTAssertEqual(distanceCM, 10)
        XCTAssertEqual(turnDirection, .right)
        XCTAssertEqual(degrees, 90)
        XCTAssertEqual(seconds, 1)
    }
}
