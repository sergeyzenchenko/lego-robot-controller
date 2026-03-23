import Foundation

// MARK: - Agent Executor

@MainActor
struct AgentExecutor {
    let robotViewModel: RobotViewModel

    typealias Result = RobotExecutionResult

    func execute(actions: [AgentAction]) async -> Result {
        return await robotViewModel.execute(
            commands: AgentCommandMapper.commands(for: actions, initialLEDState: robotViewModel.ledState),
            capturesFinalObservation: true
        )
    }
}
