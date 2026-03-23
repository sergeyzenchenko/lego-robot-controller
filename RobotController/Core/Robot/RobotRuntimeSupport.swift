import Foundation

enum AppLog {
    static func debug(_ message: @autoclosure () -> String) {
#if DEBUG
        guard !ProcessInfo.processInfo.isRunningTests else { return }
        print(message())
#endif
    }

    static func error(_ message: @autoclosure () -> String) {
        debug(message())
    }
}

// MARK: - Runtime Command Types

enum RobotCommand {
    case move(direction: AgentDirection, distanceCM: Int)
    case turn(direction: AgentDirection, degrees: Int)
    case look(direction: AgentDirection)
    case setLEDs(LEDState)
    case wait(seconds: Double)
    case stop
}

struct RobotExecutionResult {
    let log: [String]
    let photoBase64: String?
    let depthPayload: AgentDepthPayload
    let depthText: String
    let lookPhotos: [(direction: String, photoBase64: String)]
    let completed: Bool
}

enum RobotOperationStatus: Equatable {
    case idle
    case running
}

// MARK: - Runtime Protocols

@MainActor
protocol RobotCommandDriving: AnyObject {
    var ledState: LEDState { get }
    func sendMotor(_ command: MotorCommand)
    func setLEDState(_ state: LEDState)
}

protocol RobotPhotoCapturing {
    func capturePhoto() async throws -> Data
}

protocol RobotDepthSensing {
    func captureDepth() async -> AgentDepthPayload
}

protocol RobotPerceptionProviding {
    func capturePhoto() async throws -> Data
    func captureDepth() async -> AgentDepthPayload
}

protocol RobotClock {
    func sleep(for duration: Duration) async throws
}

@MainActor
protocol RobotSpeechSynthesizing: AnyObject {
    func speak(_ text: String, apiKey: String, voice: String) async
}

struct DefaultCameraCaptureAdapter: RobotPhotoCapturing {
    func capturePhoto() async throws -> Data {
        try await CameraCapture.capturePhoto()
    }
}

struct DefaultDepthSensorAdapter: RobotDepthSensing {
    func captureDepth() async -> AgentDepthPayload {
        await DepthCaptureManager.shared.captureDepth()
    }
}

struct DefaultRobotPerceptionProvider: RobotPerceptionProviding {
    private let photoCapture: any RobotPhotoCapturing
    private let depthSensor: any RobotDepthSensing

    init(
        photoCapture: any RobotPhotoCapturing = DefaultCameraCaptureAdapter(),
        depthSensor: any RobotDepthSensing = DefaultDepthSensorAdapter()
    ) {
        self.photoCapture = photoCapture
        self.depthSensor = depthSensor
    }

    func capturePhoto() async throws -> Data {
        try await photoCapture.capturePhoto()
    }

    func captureDepth() async -> AgentDepthPayload {
        await depthSensor.captureDepth()
    }
}

struct SystemRobotClock: RobotClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
final class DefaultRobotSpeechSynthesizer: RobotSpeechSynthesizing {
    private let tts: any TTSManaging

    init(tts: (any TTSManaging)? = nil) {
        self.tts = tts ?? TTSManager()
    }

    func speak(_ text: String, apiKey: String, voice: String = "shimmer") async {
        await tts.speak(text, apiKey: apiKey, voice: voice)
    }
}

// MARK: - Shared Command Executor

actor RobotCommandExecutor {
    private weak var driver: (any RobotCommandDriving)?
    private let perception: any RobotPerceptionProviding
    private let clock: any RobotClock

    private static let maxMoveDistanceCM = 35

    init(
        driver: any RobotCommandDriving,
        perception: any RobotPerceptionProviding = DefaultRobotPerceptionProvider(),
        clock: any RobotClock = SystemRobotClock()
    ) {
        self.driver = driver
        self.perception = perception
        self.clock = clock
    }

    func execute(commands: [RobotCommand], capturesFinalObservation: Bool = true) async -> RobotExecutionResult {
        var log: [String] = []
        var lookPhotos: [(String, String)] = []

        for command in commands {
            guard !Task.isCancelled else {
                return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
            }

            switch command {
            case .move(let direction, let requestedCM):
                guard let driver else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                let cm = clampMoveDistance(requestedCM)
                let seconds = max(Double(cm) / 3.5, 0.5)
                let motorCommand: MotorCommand = direction == .backward ? .backward : .forward

                let depthBefore = await perception.captureDepth()
                await driver.sendMotor(motorCommand)
                guard await sleepForMotion(.seconds(seconds)) else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                await driver.sendMotor(.stop)
                guard await sleepForDuration(.milliseconds(200)) else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }

                let depthAfter = await perception.captureDepth()
                let measured = LiDARMeasurement.measureDistance(
                    before: depthBefore,
                    after: depthAfter,
                    direction: direction.rawValue
                )
                log.append(LiDARMeasurement.formatMoveLog(direction: direction.rawValue, requestedCM: cm, measuredCM: measured))

            case .turn(let direction, let requestedDegrees):
                guard let driver else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                let degrees = max(requestedDegrees, 1)
                let seconds = Double(degrees) / 28.0
                let motorCommand: MotorCommand = direction == .left ? .spinLeft : .spinRight

                let depthBefore = await perception.captureDepth()
                await driver.sendMotor(motorCommand)
                guard await sleepForMotion(.seconds(seconds)) else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                await driver.sendMotor(.stop)
                guard await sleepForDuration(.milliseconds(200)) else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }

                let depthAfter = await perception.captureDepth()
                let measured = LiDARMeasurement.measureTurn(before: depthBefore, after: depthAfter)
                log.append(LiDARMeasurement.formatTurnLog(direction: direction.rawValue, requestedDeg: degrees, measuredDeg: measured))

            case .look(let direction):
                guard let driver else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                let degrees: Int
                switch direction {
                case .left: degrees = 90
                case .right: degrees = 90
                case .behind: degrees = 180
                default: degrees = 90
                }
                let turnCommand: MotorCommand = direction == .right ? .spinRight : .spinLeft
                let returnCommand: MotorCommand = direction == .right ? .spinLeft : .spinRight

                await driver.sendMotor(turnCommand)
                guard await sleepForMotion(.seconds(Double(degrees) / 28.0)) else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                await driver.sendMotor(.stop)
                guard await sleepForDuration(.milliseconds(300)) else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }

                if let photo = try? await perception.capturePhoto() {
                    lookPhotos.append((direction.rawValue, photo.base64EncodedString()))
                }

                await driver.sendMotor(returnCommand)
                guard await sleepForMotion(.seconds(Double(degrees) / 28.0)) else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                await driver.sendMotor(.stop)
                log.append("Looked \(direction.rawValue)")

            case .setLEDs(let state):
                guard let driver else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                await driver.setLEDState(state)
                log.append("LEDs L=\(state.left ? "on" : "off") R=\(state.right ? "on" : "off")")

            case .wait(let seconds):
                let clamped = min(max(seconds, 0), 10)
                guard await sleepForDuration(.seconds(clamped)) else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                log.append("Waited \(String(format: "%.1f", clamped))s")

            case .stop:
                guard let driver else {
                    return await finalObservation(log: log, lookPhotos: lookPhotos, completed: false, capturesFinalObservation: capturesFinalObservation)
                }
                await driver.sendMotor(.stop)
                log.append("Stopped")
            }
        }

        return await finalObservation(log: log, lookPhotos: lookPhotos, completed: !Task.isCancelled, capturesFinalObservation: capturesFinalObservation)
    }

    private func clampMoveDistance(_ cm: Int) -> Int {
        min(max(cm, 1), Self.maxMoveDistanceCM)
    }

    private func sleepForMotion(_ duration: Duration) async -> Bool {
        do {
            try await clock.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            if let driver {
                await driver.sendMotor(.stop)
            }
            return false
        }
    }

    private func sleepForDuration(_ duration: Duration) async -> Bool {
        do {
            try await clock.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func finalObservation(
        log: [String],
        lookPhotos: [(String, String)],
        completed: Bool,
        capturesFinalObservation: Bool
    ) async -> RobotExecutionResult {
        if let driver {
            await driver.sendMotor(.stop)
        }

        guard capturesFinalObservation else {
            return RobotExecutionResult(
                log: log,
                photoBase64: nil,
                depthPayload: .unavailable,
                depthText: AgentDepthPayload.unavailable.textDescription,
                lookPhotos: lookPhotos,
                completed: completed
            )
        }

        var photoBase64: String?
        if let photo = try? await perception.capturePhoto() {
            photoBase64 = photo.base64EncodedString()
        }
        let depth = await perception.captureDepth()

        return RobotExecutionResult(
            log: log,
            photoBase64: photoBase64,
            depthPayload: depth,
            depthText: depth.textDescription,
            lookPhotos: lookPhotos,
            completed: completed
        )
    }
}
