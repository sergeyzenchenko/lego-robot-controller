import Foundation

@MainActor
final class RobotRuntime: ObservableObject, RobotTransportDelegate, RobotCommandDriving {
    @Published var connectionPhase: RobotConnectionPhase = .idle
    @Published var sensorData: SensorData?
    @Published var ledState = LEDState()
    @Published private(set) var operationStatus: RobotOperationStatus = .idle

    let transport: RobotTransport

    private let perception: any RobotPerceptionProviding
    private let clock: any RobotClock
    private let speechSynthesizer: any RobotSpeechSynthesizing
    private lazy var executor = RobotCommandExecutor(driver: self, perception: perception, clock: clock)
    private var currentOperationTask: Task<RobotExecutionResult, Never>?
    private var currentOperationID = UUID()

    init(
        transport: RobotTransport,
        perception: any RobotPerceptionProviding = DefaultRobotPerceptionProvider(),
        clock: any RobotClock = SystemRobotClock(),
        speechSynthesizer: (any RobotSpeechSynthesizing)? = nil
    ) {
        self.transport = transport
        self.perception = perception
        self.clock = clock
        self.speechSynthesizer = speechSynthesizer ?? DefaultRobotSpeechSynthesizer()
        transport.delegate = self
    }

    var isConnected: Bool { connectionPhase.isReady }

    func connect() {
        transport.connect()
    }

    func disconnect() {
        cancelCurrentOperation()
        transport.disconnect()
    }

    func sendMotor(_ command: MotorCommand) {
        transport.writeMotors(command.data)
    }

    func setLEDState(_ state: LEDState) {
        ledState = state
        transport.writeLEDs(Data([state.byte]))
    }

    func toggleLeftLED() {
        var next = ledState
        next.left.toggle()
        setLEDState(next)
    }

    func toggleRightLED() {
        var next = ledState
        next.right.toggle()
        setLEDState(next)
    }

    func execute(commands: [RobotCommand], capturesFinalObservation: Bool = true) async -> RobotExecutionResult {
        cancelCurrentOperation()

        let operationID = UUID()
        currentOperationID = operationID
        operationStatus = .running

        let task = Task { [executor] in
            await executor.execute(commands: commands, capturesFinalObservation: capturesFinalObservation)
        }
        currentOperationTask = task

        let result = await task.value
        if currentOperationID == operationID {
            currentOperationTask = nil
            operationStatus = .idle
        }
        return result
    }

    func cancelCurrentOperation() {
        currentOperationTask?.cancel()
        currentOperationTask = nil
        currentOperationID = UUID()
        operationStatus = .idle
        sendMotor(.stop)
    }

    func capturePhoto() async throws -> Data {
        try await perception.capturePhoto()
    }

    func captureDepth() async -> AgentDepthPayload {
        await perception.captureDepth()
    }

    func speak(_ text: String, apiKey: String, voice: String = "shimmer") async {
        await speechSynthesizer.speak(text, apiKey: apiKey, voice: voice)
    }

    func transportDidChangePhase(_ phase: RobotConnectionPhase) {
        connectionPhase = phase
        if phase == .disconnected || phase == .unavailable {
            cancelCurrentOperation()
            sensorData = nil
            ledState = LEDState()
        }
    }

    func transportDidReceiveSensor(_ data: SensorData) {
        sensorData = data
    }
}
