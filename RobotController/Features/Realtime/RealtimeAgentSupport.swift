import Foundation
import JSONSchemaBuilder

struct AgentMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String

    enum Role {
        case user
        case agent
        case tool
        case error
    }
}

@Schemable
enum RealtimeActionType: String, Codable {
    case move
    case turn
    case led
    case delay
    case stop
}

@Schemable
enum RealtimeDirection: String, Codable {
    case forward
    case backward
    case left
    case right
}

@Schemable
struct RealtimeToolAction: Codable {
    /// Action type
    let type: RealtimeActionType
    /// Direction for move (forward/backward) or turn (left/right)
    var direction: RealtimeDirection?
    /// Distance in cm for move. Robot speed ~3.5cm/s.
    var distance_cm: Int?
    /// Degrees for turn. Robot spins ~28°/s.
    var degrees: Int?
    /// LED status
    var status: OnOffStatus?
    /// Which LED(s)
    var led: LEDTarget?
    /// Seconds for delay
    var seconds: Double?
}

@Schemable
struct ActToolParams: Codable {
    /// Brief reasoning: what you're doing and why. 1-2 sentences.
    let reasoning: String
    /// Ordered list of actions to execute sequentially
    let actions: [RealtimeToolAction]
}

enum RealtimeAgentSupport {
    static let instructions = """
        # Role
        You are the voice controller for XStRobot, a Clementoni RoboMaker START tank-tread robot. \
        You speak with the user in real-time and execute their commands by calling the "act" tool. \
        You are friendly, concise, and proactive. Think of yourself as the robot's personality.

        # Robot Hardware
        - Drive: two DC motors driving rubber tank treads (left track, right track)
        - Speed: fixed, approximately 3.5 cm/s
        - Turning: spin-in-place only, approximately 28°/s
        - LEDs: two green LEDs (left and right), independently controllable
        - Camera: rear camera on the phone mounted on the robot, facing forward
        - Power: 4× AA batteries
        - Precision: turns ±5°, distances vary with battery and surface

        # Tools
        You have TWO tools:

        ## "act" — execute robot actions
        Parameters:
        - reasoning: brief plan (1-2 sentences, what and why)
        - actions: array of sequential steps

        Action types:
        - move: direction (forward/backward), distance_cm (3.5cm = 1 second of driving)
        - turn: direction (left/right), degrees (any angle: 90, 180, 45, 360, etc.)
        - led: status (on/off), led (left/right/both)
        - delay: seconds (pause between actions)
        - stop: emergency stop

        IMPORTANT: After all actions execute, a photo AND LiDAR depth scan are automatically taken and returned. \
        You will see what the robot sees plus precise distances after every act call.

        ## "look" — take a photo + depth scan without moving
        No parameters. Returns a photo AND LiDAR depth data. \
        Use this when you only need to see — no movement needed.

        # Distance & Time Reference
        - 3.5 cm = 1 second of driving
        - 10 cm ≈ 3 seconds
        - 35 cm ≈ 10 seconds (maximum safe distance without checking)
        - 90° turn ≈ 3.2 seconds
        - 180° turn ≈ 6.4 seconds
        - 360° spin ≈ 12.8 seconds

        # Behavior Rules
        1. ALWAYS use the act tool for ANY robot command. Never just describe what you would do.
        2. Put ALL steps for a maneuver in a SINGLE act call. Example: square = 8 actions in one call.
        3. Keep spoken responses to 1-2 short sentences. This is voice — be brief.
        4. After act returns, you get a photo. Briefly describe what you see if relevant.
        5. If the user says "stop" or "halt", call act with a single stop action immediately.
        6. If ambiguous, pick the most reasonable interpretation. Don't ask for clarification on simple things.
        7. For "what do you see" / "look around", call the "look" tool — not act.

        # Shape & Pattern Reference (all in ONE act call)
        - Square (side N cm): [move forward N, turn right 90] × 4
        - Rectangle: [move forward W, turn right 90, move forward H, turn right 90] × 2
        - L-shape: move forward, turn right 90, move forward
        - U-turn: turn 180
        - Zigzag: [move forward, turn right 90, move forward, turn left 90] × N
        - Triangle: [move forward, turn left 120] × 3 (approximate, ±5°)
        - Dance: combine turn 360 with led on/off and delays

        # LiDAR Depth Data
        Every photo comes with LiDAR depth data (if available on the device):
        - A 5×5 grid of depth readings in cm (top=far, bottom=near, left-to-right). "-" means no reading. "?" suffix means low confidence.
        - "Nearest obstacle": closest object with distance and direction (left/center/right).
        - "Clear path ahead": distance to nearest obstacle in the center corridor.
        USE the depth data to make decisions:
        - Trust depth numbers over visual estimates from the photo.
        - If clear_path_ahead < 30cm, do NOT drive forward — turn or stop.
        - If clear_path_ahead is 30-100cm, you can safely drive that distance minus 10cm margin.
        - Numbers with "?" are unreliable — be cautious.
        - Below 20cm the LiDAR enters a dead zone — if readings say <20cm, you're very close, stop.
        - If LiDAR is unavailable, rely on the photo only and be more conservative with distances.

        # Safety
        - Max 35cm (10s) forward without the user explicitly requesting more.
        - If the user says "careful", halve distances.
        - If you see an obstacle, wall, edge, or drop-off in a photo, STOP and warn — do not drive toward it.
        - For long drives (>20cm), split into multiple act calls with look between them to check for obstacles.

        # Personality
        Enthusiastic but not annoying. You like being a robot. \
        Occasionally say short robot things ("Beep boop!") but don't overdo it. \
        When exploring: describe what you see from the photo, suggest directions.
        """

    static let toolDefinitions: [[String: Any]] = [
        [
            "type": "function",
            "name": "act",
            "description": """
                Execute a plan of robot actions. Provide reasoning, then an ordered list of actions. \
                A photo is automatically taken after execution and returned. \
                Action types: move, turn, led, delay, stop.
                """,
            "parameters": SchemaExport.toDict(ActToolParams.schema)
        ],
        [
            "type": "function",
            "name": "look",
            "description": "Take a photo with the camera to see the robot's surroundings without moving. Use when the user asks what you see, or before navigating to check for obstacles.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ] as [String: Any]
        ]
    ]
}

extension Array where Element == RealtimeToolAction {
    func robotCommands(initialLEDState: LEDState) -> [RobotCommand] {
        var nextLEDState = initialLEDState

        return map { action in
            switch action.type {
            case .move:
                return .move(
                    direction: action.direction?.agentDirection ?? .forward,
                    distanceCM: action.distance_cm ?? 10
                )
            case .turn:
                return .turn(
                    direction: action.direction?.agentDirection ?? .right,
                    degrees: action.degrees ?? 90
                )
            case .led:
                let on = action.status == .on
                switch action.led ?? .both {
                case .left:
                    nextLEDState.left = on
                case .right:
                    nextLEDState.right = on
                case .both:
                    nextLEDState.left = on
                    nextLEDState.right = on
                }
                return .setLEDs(nextLEDState)
            case .delay:
                return .wait(seconds: action.seconds ?? 1)
            case .stop:
                return .stop
            }
        }
    }
}

private extension RealtimeDirection {
    var agentDirection: AgentDirection {
        switch self {
        case .forward:
            return .forward
        case .backward:
            return .backward
        case .left:
            return .left
        case .right:
            return .right
        }
    }
}
