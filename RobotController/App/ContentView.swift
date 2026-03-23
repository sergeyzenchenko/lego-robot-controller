import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: RobotViewModel
    @StateObject private var settings = LLMSettings()
    private let dependencies: RobotAppDependencies

    init(
        dependencies: RobotAppDependencies? = nil,
        transport: RobotTransport? = nil
    ) {
        let dependencies = dependencies ?? RobotAppDependencies()
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: dependencies.makeRobotViewModel(transport: transport))
    }

    var body: some View {
        MainTabView(viewModel: viewModel, settings: settings, dependencies: dependencies)
    }
}

#Preview {
    ContentView()
}
