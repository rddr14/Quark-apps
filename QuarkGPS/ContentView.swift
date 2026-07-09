import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WebViewViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        WebViewContainer(
            url: URL(string: "https://rastrear.quarkgps.com")!,
            allowedHost: "rastrear.quarkgps.com",
            viewModel: viewModel
        )
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                viewModel.markDidEnterBackground()
            case .active:
                viewModel.reloadIfAppWasBackgroundedForLongTime()
            default:
                break
            }
        }
    }
}

#Preview {
    ContentView()
}
