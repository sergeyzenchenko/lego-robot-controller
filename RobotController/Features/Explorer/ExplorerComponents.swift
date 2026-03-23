import SwiftUI

struct OccupancyMapView: View {
    let grid: OccupancyGrid
    let robotX: Double
    let robotY: Double
    let heading: Double

    var body: some View {
        Canvas { context, size in
            let (pixels, mapSize) = grid.renderMap(robotX: robotX, robotY: robotY, viewRadius: 150)
            guard mapSize > 0 else { return }

            let cellW = size.width / CGFloat(mapSize)
            let cellH = size.height / CGFloat(mapSize)

            for y in 0..<mapSize {
                for x in 0..<mapSize {
                    let pixel = pixels[y * mapSize + x]
                    let color: Color
                    if pixel.isRobot {
                        color = .blue
                    } else if pixel.isFrontier {
                        color = .yellow
                    } else {
                        switch pixel.state {
                        case .unknown:
                            color = Color(.systemGray5)
                        case .free:
                            color = .white
                        case .occupied:
                            color = .black
                        }
                    }

                    let rect = CGRect(
                        x: CGFloat(x) * cellW,
                        y: CGFloat(y) * cellH,
                        width: cellW + 0.5,
                        height: cellH + 0.5
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }

            let centerX = size.width / 2
            let centerY = size.height / 2
            let arrowLen: CGFloat = 12
            let rad = heading * .pi / 180
            let ax = centerX + CGFloat(sin(rad)) * arrowLen
            let ay = centerY - CGFloat(cos(rad)) * arrowLen

            var arrow = Path()
            arrow.move(to: CGPoint(x: centerX, y: centerY))
            arrow.addLine(to: CGPoint(x: ax, y: ay))
            context.stroke(arrow, with: .color(.red), lineWidth: 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color(.systemGray5))
    }
}

struct ExplorerStatsBar: View {
    @ObservedObject var explorer: FrontierExplorer

    var body: some View {
        HStack(spacing: 0) {
            StatItem(label: "Step", value: "\(explorer.stepCount)")
            StatItem(label: "Mapped", value: "\(explorer.grid.exploredCount)")
            StatItem(label: "Walls", value: "\(explorer.grid.occupiedCount)")
            StatItem(label: "Pos", value: "\(Int(explorer.posX)),\(Int(explorer.posY))")
            StatItem(label: "Hdg", value: "\(Int(explorer.heading))°")
        }
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.bold))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ExplorerStatusView: View {
    @ObservedObject var explorer: FrontierExplorer

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch explorer.status {
        case .idle:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .scanning:
            Image(systemName: "sensor.fill").foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .navigating:
            Image(systemName: "location.fill").foregroundStyle(.green)
                .symbolEffect(.pulse)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .stuck:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }

    private var statusText: String {
        switch explorer.status {
        case .idle:
            return "Ready to explore"
        case .scanning:
            return "Scanning with LiDAR..."
        case .navigating(let text), .done(let text), .stuck(let text):
            return text
        }
    }
}

struct ExplorerControls: View {
    @ObservedObject var explorer: FrontierExplorer
    let robotConnected: Bool

    private var isRunning: Bool {
        switch explorer.status {
        case .scanning, .navigating:
            return true
        case .idle, .done, .stuck:
            return false
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            if isRunning {
                Button {
                    explorer.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    explorer.start()
                } label: {
                    Label("Explore", systemImage: "map")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!robotConnected)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

private struct MapLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            LegendItem(color: .white, label: "Free")
            LegendItem(color: .black, label: "Wall")
            LegendItem(color: Color(.systemGray5), label: "Unknown")
            LegendItem(color: .yellow, label: "Frontier")
            LegendItem(color: .blue, label: "Robot")
        }
        .font(.caption2)
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}
