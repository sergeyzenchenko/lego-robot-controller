import SwiftUI

// MARK: - Frontier Explorer Tab

struct ExplorerView: View {
    @ObservedObject var robotViewModel: RobotViewModel
    @StateObject private var explorer: FrontierExplorer

    init(robotViewModel: RobotViewModel) {
        self.robotViewModel = robotViewModel
        _explorer = StateObject(wrappedValue: FrontierExplorer(robotViewModel: robotViewModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectionHeader(viewModel: robotViewModel)

            if !DepthCaptureManager.isSupported {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sensor.fill")
                        .font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("LiDAR Required")
                        .font(.headline).foregroundStyle(.secondary)
                    Text("Frontier exploration needs LiDAR for mapping.")
                        .font(.subheadline).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                // Map view
                OccupancyMapView(
                    grid: explorer.grid,
                    robotX: explorer.posX,
                    robotY: explorer.posY,
                    heading: explorer.heading
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)

                // Stats
                ExplorerStatsBar(explorer: explorer)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Status
                ExplorerStatusView(explorer: explorer)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                // Controls
                ExplorerControls(
                    explorer: explorer,
                    robotConnected: robotViewModel.isConnected
                )
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
