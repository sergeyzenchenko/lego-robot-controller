import Foundation

@MainActor
final class RobotControllerAssignmentStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func peripheralID(for role: RobotControllerRole) -> UUID? {
        let rawValue = defaults.string(forKey: key(for: role))
        guard let rawValue else { return nil }
        return UUID(uuidString: rawValue)
    }

    func setPeripheralID(_ id: UUID?, for role: RobotControllerRole) {
        let key = key(for: role)
        if let id {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for role: RobotControllerRole) -> String {
        "robotControllerAssignment.\(role.rawValue)"
    }
}

@MainActor
final class RobotAppDependencies {
    private let transportFactory: (RobotControllerRole) -> RobotTransport
    private let assignmentStore: RobotControllerAssignmentStore
    @available(iOS 26.0, *)
    private let voiceInputFactory: () -> VoiceInputManager
    private let realtimeAgentFactory: () -> RealtimeAgent
    private let chatViewModelFactory: (RobotViewModel, LLMSettings) -> ChatViewModel
    private let autonomousAgentFactory: (RobotViewModel, LLMSettings) -> AutonomousAgent

    init(
        transportFactory: ((RobotControllerRole) -> RobotTransport)? = nil,
        assignmentStore: RobotControllerAssignmentStore? = nil,
        voiceInputFactory: (@MainActor () -> VoiceInputManager)? = nil,
        realtimeAgentFactory: (@MainActor () -> RealtimeAgent)? = nil,
        chatViewModelFactory: (@MainActor (RobotViewModel, LLMSettings) -> ChatViewModel)? = nil,
        autonomousAgentFactory: (@MainActor (RobotViewModel, LLMSettings) -> AutonomousAgent)? = nil
    ) {
        let assignmentStore = assignmentStore ?? RobotControllerAssignmentStore()
        self.assignmentStore = assignmentStore
        self.transportFactory = transportFactory ?? {
            role in
            if ProcessInfo.processInfo.isRunningTests {
                return NoopRobotTransport()
            }
            let transport = BLETransport()
            transport.targetPeripheralIdentifier = assignmentStore.peripheralID(for: role)
            return transport
        }
        self.voiceInputFactory = voiceInputFactory ?? { VoiceInputManager() }
        self.realtimeAgentFactory = realtimeAgentFactory ?? { RealtimeAgent() }
        self.chatViewModelFactory = chatViewModelFactory ?? { robotViewModel, settings in
            ChatViewModel(robotViewModel: robotViewModel, provider: settings.makeProvider(for: robotViewModel))
        }
        self.autonomousAgentFactory = autonomousAgentFactory ?? { robotViewModel, settings in
            let key = settings.agentBackend == .gemini ? settings.geminiKey : settings.openAIKey
            return AutonomousAgent(
                robotViewModel: robotViewModel,
                apiKey: key,
                openAIKey: settings.openAIKey,
                model: settings.agentModel,
                backend: settings.agentBackend
            )
        }
    }

    func makeRobotViewModel(
        role: RobotControllerRole = .tracks,
        transport: RobotTransport? = nil
    ) -> RobotViewModel {
        RobotViewModel(transport: transport ?? transportFactory(role))
    }

    func makeAssignmentStore() -> RobotControllerAssignmentStore {
        assignmentStore
    }

    @available(iOS 26.0, *)
    func makeVoiceInputManager() -> VoiceInputManager {
        voiceInputFactory()
    }

    func makeRealtimeAgent() -> RealtimeAgent {
        realtimeAgentFactory()
    }

    func makeChatViewModel(robotViewModel: RobotViewModel, settings: LLMSettings) -> ChatViewModel {
        chatViewModelFactory(robotViewModel, settings)
    }

    func makeAutonomousAgent(robotViewModel: RobotViewModel, settings: LLMSettings) -> AutonomousAgent {
        autonomousAgentFactory(robotViewModel, settings)
    }
}

extension ProcessInfo {
    var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
