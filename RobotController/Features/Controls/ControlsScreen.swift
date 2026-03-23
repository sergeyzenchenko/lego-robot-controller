import SwiftUI

struct ControlsScreen: View {
    @ObservedObject var trackViewModel: RobotViewModel
    @ObservedObject var handsViewModel: RobotViewModel
    @StateObject private var coordinator = ControlsScreenCoordinator()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    ControlsHeaderView(
                        trackPhase: trackViewModel.connectionPhase,
                        handsPhase: handsViewModel.connectionPhase,
                        gamepadName: coordinator.isGamepadConnected ? coordinator.controllerName : nil
                    )

                    RobotAssignmentsView(
                        coordinator: coordinator,
                        trackPhase: trackViewModel.connectionPhase,
                        handsPhase: handsViewModel.connectionPhase
                    )

                    if coordinator.isBluetoothUnavailable {
                        BluetoothUnavailableCard()
                    }

                    if trackViewModel.connectionPhase.isReady {
                        TracksPanel(viewModel: trackViewModel)
                    }

                    if handsViewModel.connectionPhase.isReady {
                        HandsPanel(viewModel: handsViewModel)
                    }

                    if coordinator.isGamepadConnected {
                        GamepadPanel(
                            controllerName: coordinator.controllerName,
                            leftStick: coordinator.leftStick,
                            rightStick: coordinator.rightStick
                        )
                    }

                    if !trackViewModel.connectionPhase.isReady && !handsViewModel.connectionPhase.isReady {
                        ControlsEmptyState()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            coordinator.handleAppear(trackViewModel: trackViewModel, handsViewModel: handsViewModel)
        }
        .onDisappear {
            coordinator.handleDisappear()
        }
    }
}
