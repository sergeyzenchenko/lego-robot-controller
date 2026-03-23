import Foundation
import JSONSchemaBuilder

// MARK: - Agent Action Enums

@Schemable
enum AgentActionType: String, Codable {
    case move, turn, led, look, wait, stop
}

@Schemable
enum AgentDirection: String, Codable {
    case forward, backward, left, right, behind
}

@Schemable
enum LEDTarget: String, Codable {
    case left, right, both
}

@Schemable
enum OnOffStatus: String, Codable {
    case on, off
}

// MARK: - Agent Step (LLM response)

@Schemable
struct AgentStep: Codable {
    /// Reasoning: what do I see, what have I tried, what should I do next. 2-3 sentences.
    let thinking: String
    /// One sentence for the user. Spoken aloud when task completes or as status update.
    let summary: String
    let actions: [AgentAction]
    let decision: AgentDecision
}

@Schemable
enum AgentDecision: String, Codable {
    case `continue`
    case done
    case stuck
    case ask_user
}

@Schemable
struct AgentAction: Codable {
    let type: AgentActionType
    var direction: AgentDirection?
    var distance_cm: Int?
    var degrees: Int?
    var status: OnOffStatus?
    var led: LEDTarget?
    var seconds: Double?
}

// MARK: - Agent State

enum AgentStatus: Equatable {
    case idle
    case running
    case paused(String) // ask_user question
    case done(String)
    case failed(String)
}

struct AgentHistoryEntry {
    let step: Int
    let thinking: String
    let actionLog: String
    let decision: AgentDecision
    let observation: String
    let photoBase64: String?
    let summary: String
    let posX: Double
    let posY: Double
    let heading: Double
}

// MARK: - Agent Schema

enum AgentSchema {
    static var schemaDict: [String: Any] {
        SchemaExport.toDict(AgentStep.schema)
    }

    static var geminiSchemaDict: [String: Any] {
        SchemaExport.toGeminiDict(AgentStep.schema)
    }

    static let systemPrompt = """
        # Role
        You are the autonomous navigation brain of XStRobot, a tank-tread robot. \
        You receive a task, then plan and execute steps until complete.

        # Perception
        Each step you receive:
        - A camera photo (rear telephoto, facing forward)
        - LiDAR depth data (5x5 grid in cm, nearest obstacle, clear path ahead)
        - Your estimated position and heading (dead-reckoning, approximate)
        - Execution results from previous actions

        # Actions
        - move: forward/backward, distance_cm (speed: 3.5cm/s, max 35cm per move)
        - turn: left/right, degrees (speed: 28°/s, any angle)
        - led: on/off, left/right/both
        - look: turn to scan a direction (left/right/behind), captures a photo, turns back. \
          Use this to scout without committing to movement. Results appear in next observation.
        - wait: pause for seconds
        - stop: emergency stop

        # Decision (required every step)
        - "continue": need more steps, will observe and plan again after executing
        - "done": task complete, summary will be spoken to user
        - "stuck": cannot make progress, will report to user
        - "ask_user": need input, summary will be spoken as a question

        # Exploration Strategy
        1. Start by looking around (look left, look right) to survey the space
        2. Use depth data to find open areas — move toward them
        3. Re-scan after each move to update understanding
        4. Avoid revisiting the same area — track your heading and position
        5. For "find exit" tasks: look for doorways, hallways, large openings in depth data
        6. When you find the goal, move toward it and report done

        # Safety Rules
        - If clear_path_ahead < 30cm: do NOT move forward, turn instead
        - If nearest_obstacle < 20cm: back up first (dead zone)
        - Never move more than 35cm without observing
        - If stuck for 3+ steps: report stuck
        - Robot speed: 3.5cm/s. 10cm ≈ 3s. 35cm ≈ 10s.
        - Turn rate: 28°/s. 90° ≈ 3.2s.

        # Output
        Always respond with the AgentStep JSON. Put real reasoning in "thinking". \
        Keep "summary" natural and brief — it may be spoken aloud.
        """
}
