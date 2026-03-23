import SwiftUI

@MainActor
struct MainTabView: View {
    @ObservedObject var viewModel: RobotViewModel
    @ObservedObject var settings: LLMSettings
    let dependencies: RobotAppDependencies
    @StateObject private var handsViewModel: RobotViewModel
    @StateObject private var coordinator: MainTabCoordinator

    init(
        viewModel: RobotViewModel,
        settings: LLMSettings,
        dependencies: RobotAppDependencies
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.dependencies = dependencies
        _handsViewModel = StateObject(
            wrappedValue: dependencies.makeRobotViewModel(role: .hands)
        )
        _coordinator = StateObject(
            wrappedValue: MainTabCoordinator(
                robotViewModel: viewModel,
                settings: settings,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        TabView {
            Tab("Controls", systemImage: "gamecontroller") {
                ControlsScreen(trackViewModel: viewModel, handsViewModel: handsViewModel)
            }
            Tab("Chat", systemImage: "bubble.left.and.text.bubble.right") {
                NavigationStack {
                    if let chatViewModel = coordinator.chatViewModel {
                        VStack(spacing: 0) {
                            ConnectionHeader(viewModel: viewModel)
                            ChatView(
                                chatViewModel: chatViewModel,
                                robotViewModel: viewModel,
                                makeVoiceInputManager: dependencies.makeVoiceInputManager
                            )
                        }
                        .navigationTitle("Chat")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                settingsButton
                            }
                        }
                    }
                }
            }
            Tab("Auto", systemImage: "map") {
                NavigationStack {
                    AutonomousAgentView(
                        robotViewModel: viewModel,
                        settings: settings,
                        makeVoiceInputManager: dependencies.makeVoiceInputManager,
                        makeAgent: dependencies.makeAutonomousAgent
                    )
                    .navigationTitle("Autonomous")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab("Explore", systemImage: "map.fill") {
                NavigationStack {
                    ExplorerView(robotViewModel: viewModel)
                        .navigationTitle("Explore")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab("Depth", systemImage: "sensor.fill") {
                NavigationStack {
                    DepthDebugView()
                        .navigationTitle("LiDAR")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab("Agent", systemImage: "waveform.and.mic") {
                NavigationStack {
                    RealtimeAgentView(
                        robotViewModel: viewModel,
                        settings: settings,
                        makeAgent: dependencies.makeRealtimeAgent
                    )
                    .navigationTitle("Voice Agent")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            settingsButton
                        }
                    }
                }
            }
        }
        .onAppear { coordinator.refreshChatViewModelIfNeeded() }
        .onChange(of: settings.providerType) { coordinator.refreshChatViewModelIfNeeded() }
        .onChange(of: settings.openAIKey) { coordinator.refreshChatViewModelIfNeeded() }
        .onChange(of: settings.openAIModel) { coordinator.refreshChatViewModelIfNeeded() }
        .onChange(of: settings.geminiKey) { coordinator.refreshChatViewModelIfNeeded() }
        .onChange(of: settings.geminiModel) { coordinator.refreshChatViewModelIfNeeded() }
        .sheet(isPresented: $coordinator.isShowingSettings) {
            LLMSettingsView(settings: settings)
        }
    }

    private var settingsButton: some View {
        Button(action: coordinator.presentSettings) {
            Image(systemName: "gearshape")
        }
    }
}
