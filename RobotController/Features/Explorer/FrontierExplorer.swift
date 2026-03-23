import Foundation

// MARK: - Frontier Explorer

/// Pure algorithmic exploration — no LLM needed.
/// Builds an occupancy grid from LiDAR, finds frontiers (boundaries between
/// known and unknown space), navigates to the nearest one. Repeats until
/// no more frontiers or max steps reached.
@MainActor
final class FrontierExplorer: ObservableObject {
    enum Status: Equatable {
        case idle
        case scanning
        case navigating(String) // description
        case done(String)
        case stuck(String)
    }

    @Published var status: Status = .idle
    @Published var stepCount = 0
    @Published var grid: OccupancyGrid
    @Published var posX: Double = 0
    @Published var posY: Double = 0
    @Published var heading: Double = 0

    private let robotViewModel: RobotViewModel
    private let maxSteps: Int
    private var task: Task<Void, Never>?

    init(robotViewModel: RobotViewModel, maxSteps: Int = 50) {
        self.robotViewModel = robotViewModel
        self.grid = OccupancyGrid(rangeCM: 500)
        self.maxSteps = maxSteps
    }

    func start() {
        guard status == .idle || isFinal else { return }
        grid = OccupancyGrid(rangeCM: 500)
        posX = 0; posY = 0; heading = 0
        stepCount = 0
        status = .scanning

        task = Task { [weak self] in
            await self?.exploreLoop()
        }
    }

    func stop() {
        task?.cancel()
        robotViewModel.sendMotor(.stop)
        status = .idle
    }

    private var isFinal: Bool {
        switch status {
        case .done, .stuck: true
        default: false
        }
    }

    // MARK: - Explore Loop

    private func exploreLoop() async {
        var stuckCount = 0

        for step in 1...maxSteps {
            guard !Task.isCancelled else { break }
            stepCount = step

            // 1. Scan: take LiDAR reading
            status = .scanning
            let depth = await robotViewModel.captureDepth()
            grid.updateFromDepth(depth, robotX: posX, robotY: posY, headingDeg: heading)

            // Also scan left and right for wider coverage
            if step <= 3 || step % 5 == 0 {
                await scanDirection("left", degrees: 90)
                await scanDirection("right", degrees: 90)
            }

            // 2. Find frontiers
            let frontiers = grid.findFrontiers(robotX: posX, robotY: posY)

            guard let target = pickBestFrontier(frontiers, depth: depth) else {
                // No frontiers left
                status = .done("Exploration complete! Mapped \(grid.exploredCount) cells, \(grid.occupiedCount) obstacles.")
                return
            }

            // 3. Navigate to frontier
            status = .navigating("→ frontier at (\(target.x), \(target.y)), \(Int(target.distance))cm away, size \(target.size)")

            let success = await navigateToward(targetX: Double(target.x), targetY: Double(target.y), clearAhead: depth.clearPathAheadCM)

            if !success {
                stuckCount += 1
                if stuckCount >= 3 {
                    // Try a random turn to unstick
                    let randomDeg = [90, 180, 270].randomElement()!
                    await turn(degrees: randomDeg, direction: .spinRight)
                    stuckCount = 0
                }
            } else {
                stuckCount = 0
            }
        }

        guard !Task.isCancelled else { return }
        if case .done = status { return }
        if case .stuck = status { return }
        if case .idle = status { return }
        status = .done("Reached \(maxSteps) steps. Mapped \(grid.exploredCount) cells.")
    }

    // MARK: - Navigation

    private func navigateToward(targetX: Double, targetY: Double, clearAhead: Int) async -> Bool {
        let dx = targetX - posX
        let dy = targetY - posY
        let targetAngle = atan2(dy, dx) * 180 / .pi
        let distance = sqrt(dx * dx + dy * dy)

        // Calculate turn needed
        var turnAngle = targetAngle - heading
        // Normalize to -180..180
        while turnAngle > 180 { turnAngle -= 360 }
        while turnAngle < -180 { turnAngle += 360 }

        // Turn toward target
        if abs(turnAngle) > 10 {
            let dir: MotorCommand = turnAngle > 0 ? .spinRight : .spinLeft
            await turn(degrees: Int(abs(turnAngle)), direction: dir)
        }

        // Drive forward (limited by clear path and 35cm max)
        let driveDist = min(distance, Double(min(clearAhead - 10, 35)))
        if driveDist < 5 { return false } // too close or blocked

        // Check path
        let targetDriveX = posX + cos(heading * .pi / 180) * driveDist
        let targetDriveY = posY + sin(heading * .pi / 180) * driveDist
        if !grid.isPathClear(fromX: posX, fromY: posY, toX: targetDriveX, toY: targetDriveY) {
            return false // path blocked
        }

        await drive(distanceCM: driveDist)
        return true
    }

    private func scanDirection(_ dir: String, degrees: Int) async {
        let cmd: MotorCommand = dir == "right" ? .spinRight : .spinLeft
        let returnCmd: MotorCommand = dir == "right" ? .spinLeft : .spinRight

        // Turn
        await turn(degrees: degrees, direction: cmd)
        guard !Task.isCancelled else { return }

        // Scan
        let depth = await robotViewModel.captureDepth()
        grid.updateFromDepth(depth, robotX: posX, robotY: posY, headingDeg: heading)
        guard !Task.isCancelled else { return }

        // Turn back
        await turn(degrees: degrees, direction: returnCmd)
    }

    // MARK: - Primitive Actions

    private func drive(distanceCM: Double) async {
        let result = await robotViewModel.execute(
            commands: [.move(direction: .forward, distanceCM: Int(distanceCM.rounded()))],
            capturesFinalObservation: false
        )
        guard result.completed else { return }

        // Update dead-reckoning
        let rad = heading * .pi / 180
        posX += cos(rad) * distanceCM
        posY += sin(rad) * distanceCM
    }

    private func turn(degrees: Int, direction: MotorCommand) async {
        let turnDirection: AgentDirection = direction == .spinRight ? .right : .left
        let result = await robotViewModel.execute(
            commands: [.turn(direction: turnDirection, degrees: degrees)],
            capturesFinalObservation: false
        )
        guard result.completed else { return }

        // Update heading
        if direction == .spinRight {
            heading += Double(degrees)
        } else {
            heading -= Double(degrees)
        }
        // Normalize
        while heading > 360 { heading -= 360 }
        while heading < 0 { heading += 360 }
    }

    // MARK: - Frontier Selection

    private func pickBestFrontier(_ frontiers: [OccupancyGrid.Frontier], depth: AgentDepthPayload) -> OccupancyGrid.Frontier? {
        guard !frontiers.isEmpty else { return nil }

        // Score: prefer larger frontiers that are closer
        // score = size / (distance + 10) — bias toward big nearby frontiers
        let scored = frontiers.map { f in
            (frontier: f, score: Double(f.size) / (f.distance + 10))
        }

        return scored.max(by: { $0.score < $1.score })?.frontier
    }

}
