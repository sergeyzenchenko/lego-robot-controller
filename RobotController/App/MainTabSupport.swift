import SwiftUI

@MainActor
final class MainTabCoordinator: ObservableObject {
    @Published private(set) var chatViewModel: ChatViewModel?
    @Published var isShowingSettings = false

    private let robotViewModel: RobotViewModel
    private let settings: LLMSettings
    private let dependencies: RobotAppDependencies
    private var currentProviderConfig: LLMProviderConfiguration?

    init(
        robotViewModel: RobotViewModel,
        settings: LLMSettings,
        dependencies: RobotAppDependencies
    ) {
        self.robotViewModel = robotViewModel
        self.settings = settings
        self.dependencies = dependencies
    }

    func presentSettings() {
        isShowingSettings = true
    }

    func refreshChatViewModelIfNeeded() {
        let nextConfig = settings.providerConfiguration
        let needsRecreate = currentProviderConfig != nextConfig || chatViewModel == nil
        guard needsRecreate else { return }

        chatViewModel = dependencies.makeChatViewModel(
            robotViewModel: robotViewModel,
            settings: settings
        )
        currentProviderConfig = nextConfig
    }
}
