import SwiftUI

struct DepthDebugView: View {
    @StateObject private var viewModel = DepthDebugViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if !DepthCaptureManager.isSupported {
                UnsupportedView()
            } else if let snapshot = viewModel.snapshot {
                DepthDebugSnapshotView(snapshot: snapshot)
            } else {
                DepthDebugLoadingView()
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}
