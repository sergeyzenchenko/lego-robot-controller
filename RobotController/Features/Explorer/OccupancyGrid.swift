import Foundation

// MARK: - Cell State

enum CellState: UInt8 {
    case unknown = 0
    case free = 1
    case occupied = 2
}

// MARK: - Occupancy Grid

/// 2D grid map built from LiDAR scans. Each cell is 5cm × 5cm.
/// Origin (0,0) is where the robot started. Coordinates in cm, grid indices in cells.
final class OccupancyGrid {
    let cellSize: Double = 5.0 // cm per cell
    let gridSize: Int // cells per side

    private var cells: [CellState]
    private let halfGrid: Int // offset so (0,0) is center

    /// Creates a grid covering ±rangeCM in each direction
    init(rangeCM: Double = 500) {
        gridSize = Int(rangeCM * 2 / 5.0) + 1 // e.g., 500cm range → 201 cells
        halfGrid = gridSize / 2
        cells = [CellState](repeating: .unknown, count: gridSize * gridSize)
    }

    // MARK: - Access

    func state(atX x: Int, y: Int) -> CellState {
        let (gx, gy) = toGrid(x, y)
        guard inBounds(gx, gy) else { return .unknown }
        return cells[gy * gridSize + gx]
    }

    func set(_ state: CellState, atX x: Int, y: Int) {
        let (gx, gy) = toGrid(x, y)
        guard inBounds(gx, gy) else { return }
        let idx = gy * gridSize + gx
        // Don't downgrade occupied to free (walls are sticky)
        if state == .free && cells[idx] == .occupied { return }
        cells[idx] = state
    }

    // MARK: - Raycasting from LiDAR

    /// Update grid from a LiDAR depth payload + robot position/heading.
    /// Casts rays from the robot position through the depth grid, marking free cells along the ray
    /// and occupied at the endpoint.
    func updateFromDepth(_ depth: AgentDepthPayload, robotX: Double, robotY: Double, headingDeg: Double) {
        guard depth.lidarAvailable else { return }

        let headingRad = headingDeg * .pi / 180

        // The 5×5 depth grid covers the camera FOV.
        // Approximate: horizontal FOV ≈ 40° (telephoto), vertical ≈ 54°
        // Each grid column spans ~8° horizontally
        let hFOV = 40.0 * .pi / 180
        let cols = depth.grid5x5.first?.count ?? 5

        for (_, row) in depth.grid5x5.enumerated() {
            for (col, cell) in row.enumerated() {
                guard let distCM = cell.distanceCM, cell.confidence != "low" else { continue }

                // Angle offset for this column: leftmost = -hFOV/2, rightmost = +hFOV/2
                let colFraction = (Double(col) + 0.5) / Double(cols) - 0.5 // -0.5..0.5
                let rayAngle = headingRad + colFraction * hFOV

                let dist = Double(distCM)

                // Mark free cells along the ray
                let stepCM = cellSize
                var d = stepCM
                while d < dist - cellSize {
                    let fx = robotX + cos(rayAngle) * d
                    let fy = robotY + sin(rayAngle) * d
                    set(.free, atX: Int(fx), y: Int(fy))
                    d += stepCM
                }

                // Mark occupied cell at endpoint (if within reasonable range)
                if dist < 400 {
                    let ox = robotX + cos(rayAngle) * dist
                    let oy = robotY + sin(rayAngle) * dist
                    set(.occupied, atX: Int(ox), y: Int(oy))
                }
            }
        }

        // Mark robot position as free
        set(.free, atX: Int(robotX), y: Int(robotY))
    }

    // MARK: - Frontier Detection

    struct Frontier {
        let x: Int // cm
        let y: Int // cm
        let size: Int // number of frontier cells in cluster
        let distance: Double // from robot
    }

    /// Find frontiers: free cells adjacent to unknown cells.
    /// Clusters them and returns sorted by distance from robot.
    func findFrontiers(robotX: Double, robotY: Double) -> [Frontier] {
        var frontierCells: [(Int, Int)] = [] // grid coords

        for gy in 1..<(gridSize - 1) {
            for gx in 1..<(gridSize - 1) {
                guard cells[gy * gridSize + gx] == .free else { continue }

                // Check 4-neighbors for unknown
                let hasUnknown =
                    cells[(gy - 1) * gridSize + gx] == .unknown ||
                    cells[(gy + 1) * gridSize + gx] == .unknown ||
                    cells[gy * gridSize + (gx - 1)] == .unknown ||
                    cells[gy * gridSize + (gx + 1)] == .unknown

                if hasUnknown {
                    frontierCells.append((gx, gy))
                }
            }
        }

        guard !frontierCells.isEmpty else { return [] }

        // Simple clustering: group adjacent frontier cells using flood fill
        var visited = Set<Int>()
        var clusters: [[(Int, Int)]] = []

        for cell in frontierCells {
            let key = cell.1 * gridSize + cell.0
            guard !visited.contains(key) else { continue }

            var cluster: [(Int, Int)] = []
            var queue = [cell]
            visited.insert(key)

            while !queue.isEmpty {
                let c = queue.removeFirst()
                cluster.append(c)

                for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nx = c.0 + dx
                    let ny = c.1 + dy
                    let nk = ny * gridSize + nx
                    guard !visited.contains(nk) else { continue }
                    guard frontierCells.contains(where: { $0.0 == nx && $0.1 == ny }) else { continue }
                    visited.insert(nk)
                    queue.append((nx, ny))
                }
            }

            clusters.append(cluster)
        }

        // Convert clusters to Frontier objects
        return clusters
            .filter { $0.count >= 2 } // ignore tiny 1-cell frontiers
            .map { cluster in
                let cx = cluster.map(\.0).reduce(0, +) / cluster.count
                let cy = cluster.map(\.1).reduce(0, +) / cluster.count
                let (wx, wy) = fromGrid(cx, cy)
                let dist = sqrt(pow(Double(wx) - robotX, 2) + pow(Double(wy) - robotY, 2))
                return Frontier(x: wx, y: wy, size: cluster.count, distance: dist)
            }
            .sorted { $0.distance < $1.distance }
    }

    // MARK: - Path Check

    /// Simple line-of-sight check: is the straight line from A to B free of occupied cells?
    func isPathClear(fromX: Double, fromY: Double, toX: Double, toY: Double) -> Bool {
        let dx = toX - fromX
        let dy = toY - fromY
        let dist = sqrt(dx * dx + dy * dy)
        let steps = Int(dist / cellSize) + 1

        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let px = fromX + dx * t
            let py = fromY + dy * t
            if state(atX: Int(px), y: Int(py)) == .occupied {
                return false
            }
        }
        return true
    }

    // MARK: - Map Rendering (for UI)

    struct MapPixel {
        let state: CellState
        let isFrontier: Bool
        let isRobot: Bool
    }

    func renderMap(robotX: Double, robotY: Double, viewRadius: Int = 100) -> (pixels: [MapPixel], size: Int) {
        // Render a square region around the robot
        let (rcx, rcy) = toGrid(Int(robotX), Int(robotY))
        let viewCells = viewRadius / Int(cellSize)
        let renderSize = viewCells * 2 + 1

        // Pre-compute frontiers
        let frontierSet = Set(findFrontiers(robotX: robotX, robotY: robotY).map { toGrid($0.x, $0.y) }.map { $0.0 * 10000 + $0.1 })

        var pixels: [MapPixel] = []
        pixels.reserveCapacity(renderSize * renderSize)

        let robotGX = rcx
        let robotGY = rcy

        for dy in -viewCells...viewCells {
            for dx in -viewCells...viewCells {
                let gx = rcx + dx
                let gy = rcy + dy
                let state = inBounds(gx, gy) ? cells[gy * gridSize + gx] : .unknown
                let isFrontier = frontierSet.contains(gx * 10000 + gy)
                let isRobot = gx == robotGX && gy == robotGY
                pixels.append(MapPixel(state: state, isFrontier: isFrontier, isRobot: isRobot))
            }
        }

        return (pixels, renderSize)
    }

    // MARK: - Stats

    var exploredCount: Int { cells.filter { $0 != .unknown }.count }
    var occupiedCount: Int { cells.filter { $0 == .occupied }.count }
    var totalCells: Int { gridSize * gridSize }

    // MARK: - Coordinate Conversion

    private func toGrid(_ x: Int, _ y: Int) -> (Int, Int) {
        (x / Int(cellSize) + halfGrid, y / Int(cellSize) + halfGrid)
    }

    private func fromGrid(_ gx: Int, _ gy: Int) -> (Int, Int) {
        ((gx - halfGrid) * Int(cellSize), (gy - halfGrid) * Int(cellSize))
    }

    private func inBounds(_ gx: Int, _ gy: Int) -> Bool {
        gx >= 0 && gx < gridSize && gy >= 0 && gy < gridSize
    }
}
