import Foundation
import FoundationModels

// MARK: - @Generable mirrors of plan types for Foundation Models

@available(iOS 26.0, *)
@Generable(description: "Type of user command")
enum OnDeviceUserIntent {
    case drive, turn, shape, lights, stop, combo
}

@available(iOS 26.0, *)
@Generable(description: "Move duration")
struct OnDeviceMoveParams {
    @Guide(description: "Seconds to drive (1-10)", .range(1...10))
    var duration: Int
}

@available(iOS 26.0, *)
@Generable(description: "LED state")
struct OnDeviceLEDParams {
    var leftOn: Bool
    var rightOn: Bool
}

@available(iOS 26.0, *)
@Generable(description: "A robot action")
enum OnDeviceRobotAction {
    case moveForward(OnDeviceMoveParams)
    case moveBackward(OnDeviceMoveParams)
    case turnLeft90
    case turnRight90
    case turnAround
    case spin360
    case stop
    case setLEDs(OnDeviceLEDParams)
}

@available(iOS 26.0, *)
@Generable(description: "Robot control plan")
struct OnDeviceRobotPlan {
    @Guide(description: "What type of command is this")
    var intent: OnDeviceUserIntent

    @Guide(description: "Brief plan: what actions in what order. For shapes specify side count and turns. 1-2 sentences max.")
    var reasoning: String

    @Guide(description: "Actions to execute in order", .maximumCount(20))
    var actions: [OnDeviceRobotAction]
}

// MARK: - Conversion to domain types

@available(iOS 26.0, *)
extension OnDeviceRobotPlan {
    func toDomain() -> RobotPlan {
        RobotPlan(
            intent: intent.toDomain(),
            reasoning: reasoning,
            actions: actions.map { $0.toDomain() }
        )
    }
}

@available(iOS 26.0, *)
extension OnDeviceUserIntent {
    func toDomain() -> UserIntent {
        switch self {
        case .drive:  .drive
        case .turn:   .turn
        case .shape:  .shape
        case .lights: .lights
        case .stop:   .stop
        case .combo:  .combo
        }
    }
}

@available(iOS 26.0, *)
extension OnDeviceRobotAction {
    func toDomain() -> RobotAction {
        switch self {
        case .moveForward(let p):  .moveForward(MoveParams(duration: p.duration))
        case .moveBackward(let p): .moveBackward(MoveParams(duration: p.duration))
        case .turnLeft90:          .turnLeft90
        case .turnRight90:         .turnRight90
        case .turnAround:          .turnAround
        case .spin360:             .spin360
        case .stop:                .stop
        case .setLEDs(let p):      .setLEDs(LEDParams(leftOn: p.leftOn, rightOn: p.rightOn))
        }
    }
}

// MARK: - On-Device Provider

@available(iOS 26.0, *)
@MainActor
final class OnDeviceLLMProvider: LLMProvider, ObservableObject {
    @Published private(set) var isReady = false

    private var session: LanguageModelSession?
    private static let maxHistoryPairs = 2

    private static let systemInstructions = """
        You control a tank-tread robot. Two DC motors (left/right tracks), two LEDs. \
        First classify intent, then reason briefly about the plan, then generate actions. \
        Keep reasoning to 1-2 sentences. \
        Examples: \
        square = moveForward+turnRight90 repeated 4 times (8 actions). \
        go forward 3 sec = moveForward(3). \
        turn around and come back = turnAround + moveForward.
        """

    func warmUp() async {
        guard session == nil else { return }
        AppLog.debug("[OnDevice] Creating session...")
        let instructions = Self.systemInstructions
        let s = await Task.detached {
            let s = LanguageModelSession(instructions: instructions)
            s.prewarm()
            return s
        }.value
        session = s
        isReady = true
        AppLog.debug("[OnDevice] Ready")
    }

    func generatePlan(for prompt: String) async throws -> LLMResponse {
        guard let session else { throw LLMError.notReady }

        let start = ContinuousClock.now
        do {
            let response = try await session.respond(to: prompt, generating: OnDeviceRobotPlan.self)
            let elapsed = ContinuousClock.now - start
            let plan = response.content.toDomain()
            let tokens = max(response.rawContent.jsonString.count / 4, 1)

            trimTranscript()

            return LLMResponse(plan: plan, estimatedTokens: tokens, duration: elapsed)

        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                AppLog.debug("[OnDevice] Context overflow, resetting")
                resetContext()
                // Retry once with fresh session
                let retrySession = self.session ?? LanguageModelSession(instructions: Self.systemInstructions)
                self.session = retrySession
                let response = try await retrySession.respond(to: prompt, generating: OnDeviceRobotPlan.self)
                let elapsed = ContinuousClock.now - start
                let plan = response.content.toDomain()
                let tokens = max(response.rawContent.jsonString.count / 4, 1)
                trimTranscript()
                return LLMResponse(plan: plan, estimatedTokens: tokens, duration: elapsed)
            }
            throw error
        }
    }

    func resetContext() {
        AppLog.debug("[OnDevice] Resetting session")
        session = LanguageModelSession(instructions: Self.systemInstructions)
    }

    private func trimTranscript() {
        guard let session else { return }
        let transcript = session.transcript

        var instructions: [Transcript.Entry] = []
        var pairs: [(Transcript.Entry, Transcript.Entry)] = []
        var pendingPrompt: Transcript.Entry?

        for entry in transcript {
            switch entry {
            case .instructions: instructions.append(entry)
            case .prompt: pendingPrompt = entry
            case .response:
                if let prompt = pendingPrompt {
                    pairs.append((prompt, entry))
                    pendingPrompt = nil
                }
            default: break
            }
        }

        let keepPairs = pairs.suffix(Self.maxHistoryPairs)
        let trimmed = pairs.count - keepPairs.count

        if trimmed > 0 {
            var entries = instructions
            for (prompt, response) in keepPairs {
                entries.append(prompt)
                entries.append(response)
            }
            self.session = LanguageModelSession(transcript: Transcript(entries: entries))
            AppLog.debug("[OnDevice] Trimmed \(trimmed) pairs")
        }
    }
}

enum LLMError: LocalizedError {
    case notReady
    case invalidResponse
    case apiErrorDetail(Int, String)

    var errorDescription: String? {
        switch self {
        case .notReady: "Model not ready"
        case .invalidResponse: "Invalid response from model"
        case .apiErrorDetail(let code, let msg): "API error \(code): \(msg)"
        }
    }
}
