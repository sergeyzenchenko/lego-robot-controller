import Foundation
import JSONSchemaBuilder

// MARK: - Plan Types (Codable, provider-agnostic)

@Schemable
enum UserIntent: String, Codable {
    case drive, turn, shape, lights, stop, combo
}

@Schemable
struct RobotPlan: Codable {
    var intent: UserIntent
    var reasoning: String
    var actions: [RobotAction]
}

@Schemable
struct MoveParams: Codable {
    /// Seconds to drive (1-10)
    var duration: Int
}

@Schemable
struct LEDParams: Codable {
    var leftOn: Bool
    var rightOn: Bool
}

@Schemable
enum RobotAction: Codable {
    case moveForward(MoveParams)
    case moveBackward(MoveParams)
    case turnLeft90
    case turnRight90
    case turnAround
    case spin360
    case stop
    case setLEDs(LEDParams)
}
