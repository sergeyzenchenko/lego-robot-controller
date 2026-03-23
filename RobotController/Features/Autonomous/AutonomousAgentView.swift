import SwiftUI

// MARK: - Autonomous Agent Tab

struct AutonomousAgentView: View {
    @ObservedObject var robotViewModel: RobotViewModel
    @ObservedObject var settings: LLMSettings
    @State private var agent: AutonomousAgent?
    @State private var taskInput = ""
    @State private var userReply = ""
    @StateObject private var voiceInput: VoiceInputManager
    private let makeAgent: @MainActor (RobotViewModel, LLMSettings) -> AutonomousAgent

    init(
        robotViewModel: RobotViewModel,
        settings: LLMSettings,
        makeVoiceInputManager: @escaping @MainActor () -> VoiceInputManager = { VoiceInputManager() },
        makeAgent: @escaping @MainActor (RobotViewModel, LLMSettings) -> AutonomousAgent
    ) {
        self.robotViewModel = robotViewModel
        self.settings = settings
        self.makeAgent = makeAgent
        _voiceInput = StateObject(wrappedValue: makeVoiceInputManager())
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectionHeader(viewModel: robotViewModel)

            if let agent {
                AgentRunView(
                    agent: agent,
                    robotConnected: robotViewModel.isConnected,
                    userReply: $userReply,
                    onStop: { agent.stop() },
                    onReply: {
                        agent.resumeWithUserInput(userReply)
                        userReply = ""
                    },
                    onNewTask: { self.agent = nil }
                )
            } else {
                TaskInputView(
                    taskInput: $taskInput,
                    robotConnected: robotViewModel.isConnected,
                    apiKeySet: !settings.agentAPIKey.isEmpty,
                    voiceInput: voiceInput,
                    onStart: { startTask() }
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: voiceInput.transcript) {
            if voiceInput.state == .listening {
                taskInput = voiceInput.transcript
            }
        }
    }

    private func startTask() {
        voiceInput.stopListening()
        let task = taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        let agent = makeAgent(robotViewModel, settings)
        self.agent = agent
        agent.start(task: task)
        taskInput = ""
    }
}
