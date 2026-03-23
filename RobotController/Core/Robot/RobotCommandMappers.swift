import Foundation

private enum TurnTiming {
    static let turn90: TimeInterval = 3.2
    static let turn180: TimeInterval = 6.4
    static let spin360: TimeInterval = 12.8
}

enum RobotCommandMapper {
    static func commands(for plan: RobotPlan) -> [RobotCommand] {
        plan.actions.map(command(for:))
    }

    static func command(for action: RobotAction) -> RobotCommand {
        switch action {
        case .moveForward(let params):
            let cm = min(max(params.duration, 1), 10) * 35 / 10
            return .move(direction: .forward, distanceCM: cm)
        case .moveBackward(let params):
            let cm = min(max(params.duration, 1), 10) * 35 / 10
            return .move(direction: .backward, distanceCM: cm)
        case .turnLeft90:
            return .turn(direction: .left, degrees: Int((TurnTiming.turn90 * 28).rounded()))
        case .turnRight90:
            return .turn(direction: .right, degrees: Int((TurnTiming.turn90 * 28).rounded()))
        case .turnAround:
            return .turn(direction: .left, degrees: Int((TurnTiming.turn180 * 28).rounded()))
        case .spin360:
            return .turn(direction: .left, degrees: Int((TurnTiming.spin360 * 28).rounded()))
        case .stop:
            return .stop
        case .setLEDs(let params):
            return .setLEDs(LEDState(left: params.leftOn, right: params.rightOn))
        }
    }
}
