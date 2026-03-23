import SwiftUI

@MainActor
struct RealtimeAgentView: View {
    @ObservedObject var robotViewModel: RobotViewModel
    @ObservedObject var settings: LLMSettings
    @StateObject private var agent: RealtimeAgent

    init(
        robotViewModel: RobotViewModel,
        settings: LLMSettings,
        makeAgent: @escaping @MainActor () -> RealtimeAgent = { RealtimeAgent() }
    ) {
        self.robotViewModel = robotViewModel
        self.settings = settings
        _agent = StateObject(wrappedValue: makeAgent())
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectionHeader(viewModel: robotViewModel)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if !agent.isConnected && !agent.isConnecting {
                        AgentEmptyState()
                    }

                    ForEach(agent.messages) { message in
                        AgentBubble(message: message)
                    }
                }
                .padding(.vertical, 12)
            }

            Divider()

            AgentBottomBar(
                agent: agent,
                isRobotConnected: robotViewModel.isConnected,
                onConnect: { agent.connect(apiKey: settings.openAIKey, robotViewModel: robotViewModel) },
                onDisconnect: { agent.disconnect() },
                onToggleMute: { agent.toggleMute() }
            )
        }
        .background(Color(.systemGroupedBackground))
    }
}
