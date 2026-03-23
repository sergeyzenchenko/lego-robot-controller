import Foundation

@MainActor
struct PlanExecutor {
    let robotViewModel: RobotViewModel

    func execute(_ plan: RobotPlan) async {
        _ = await robotViewModel.execute(
            commands: RobotCommandMapper.commands(for: plan),
            capturesFinalObservation: false
        )
    }
}
