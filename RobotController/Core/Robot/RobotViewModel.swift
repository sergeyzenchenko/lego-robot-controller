import Combine
import Foundation

@MainActor
final class RobotViewModel: ObservableObject {
    @Published var connectionPhase: RobotConnectionPhase = .idle
    @Published var sensorData: SensorData?
    @Published private(set) var ledState = LEDState()

    var isConnected: Bool { connectionPhase.isReady }

    let runtime: RobotRuntime
    var transport: RobotTransport { runtime.transport }

    init(runtime: RobotRuntime) {
        self.runtime = runtime
        bindRuntime()
    }

    convenience init(transport: RobotTransport) {
        self.init(runtime: RobotRuntime(transport: transport))
    }

    // MARK: - Actions

    func connect() {
        runtime.connect()
    }

    func disconnect() {
        runtime.disconnect()
    }

    func sendMotor(_ command: MotorCommand) {
        runtime.sendMotor(command)
    }

    func setLEDState(_ state: LEDState) {
        runtime.setLEDState(state)
    }

    func toggleLeftLED() {
        runtime.toggleLeftLED()
    }

    func toggleRightLED() {
        runtime.toggleRightLED()
    }

    func execute(commands: [RobotCommand], capturesFinalObservation: Bool = true) async -> RobotExecutionResult {
        await runtime.execute(commands: commands, capturesFinalObservation: capturesFinalObservation)
    }

    func cancelCurrentOperation() {
        runtime.cancelCurrentOperation()
    }

    func capturePhoto() async throws -> Data {
        try await runtime.capturePhoto()
    }

    func captureDepth() async -> AgentDepthPayload {
        await runtime.captureDepth()
    }

    func speak(_ text: String, apiKey: String, voice: String = "shimmer") async {
        await runtime.speak(text, apiKey: apiKey, voice: voice)
    }

    // MARK: - Private

    private func bindRuntime() {
        runtime.$connectionPhase
            .assign(to: &$connectionPhase)

        runtime.$sensorData
            .assign(to: &$sensorData)

        runtime.$ledState
            .assign(to: &$ledState)
    }
}
