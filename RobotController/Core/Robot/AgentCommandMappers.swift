import Foundation

enum AgentCommandMapper {
    static func commands(for actions: [AgentAction], initialLEDState: LEDState) -> [RobotCommand] {
        var nextLEDState = initialLEDState

        return actions.map { action in
            let command = command(for: action, currentLEDState: nextLEDState)
            if case .setLEDs(let state) = command {
                nextLEDState = state
            }
            return command
        }
    }

    static func command(for action: AgentAction, currentLEDState: LEDState) -> RobotCommand {
        switch action.type {
        case .move:
            return .move(direction: action.direction ?? .forward, distanceCM: action.distance_cm ?? 10)
        case .turn:
            return .turn(direction: action.direction ?? .right, degrees: action.degrees ?? 90)
        case .look:
            return .look(direction: action.direction ?? .left)
        case .led:
            var next = currentLEDState
            let on = action.status == .on
            switch action.led ?? .both {
            case .left:
                next.left = on
            case .right:
                next.right = on
            case .both:
                next.left = on
                next.right = on
            }
            return .setLEDs(next)
        case .wait:
            return .wait(seconds: action.seconds ?? 1)
        case .stop:
            return .stop
        }
    }
}
