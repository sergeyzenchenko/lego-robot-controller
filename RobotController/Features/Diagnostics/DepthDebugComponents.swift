import SwiftUI

struct DepthDebugSnapshotView: View {
    let snapshot: DepthDebugSnapshot

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(decorative: snapshot.heatmapImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                DepthDebugStatsRow(payload: snapshot.payload)
                GridView(grid: snapshot.payload.grid5x5)
                DepthDebugRawTextView(text: snapshot.payload.textDescription)
                DepthDebugTrackingView(snapshot: snapshot)
            }
            .padding()
        }
    }
}

struct DepthDebugLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Starting LiDAR...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct UnsupportedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sensor.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("LiDAR Not Available")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("This device doesn't have a LiDAR sensor.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }
}

private struct DepthDebugStatsRow: View {
    let payload: AgentDepthPayload

    var body: some View {
        HStack(spacing: 16) {
            StatPill(
                label: "Nearest",
                value: "\(payload.nearestObstacleCM)cm",
                color: pillColor(payload.nearestObstacleCM)
            )
            StatPill(
                label: "Clear",
                value: "\(payload.clearPathAheadCM)cm",
                color: pillColor(payload.clearPathAheadCM)
            )
            StatPill(label: "Direction", value: payload.nearestObstacleDirection, color: .blue)
        }
    }

    private func pillColor(_ cm: Int) -> Color {
        if cm < 20 { return .red }
        if cm < 50 { return .orange }
        return .green
    }
}

private struct DepthDebugRawTextView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DepthDebugTrackingView: View {
    let snapshot: DepthDebugSnapshot

    var body: some View {
        HStack {
            Circle()
                .fill(snapshot.isTracking ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(snapshot.trackingState)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(snapshot.fps) fps")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

private struct GridView: View {
    let grid: [[DepthCell]]

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Label("Depth Grid (cm)", systemImage: "square.grid.3x3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(0..<grid.count, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<grid[row].count, id: \.self) { col in
                        GridCellView(cell: grid[row][col])
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct GridCellView: View {
    let cell: DepthCell

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellColor)

            if let distance = cell.distanceCM {
                Text("\(distance)")
                    .font(.system(size: 11, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white)
            } else {
                Text("-")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: 32)
    }

    private var cellColor: Color {
        guard let distance = cell.distanceCM else { return .gray.opacity(0.3) }
        if cell.confidence == "low" { return .gray }
        if distance < 30 { return .red }
        if distance < 80 { return .orange }
        if distance < 150 { return .yellow.opacity(0.8) }
        return .green
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
