import SwiftUI

@main
struct OpenScanApp: App {
    @State private var session = ScanSession()
    @State private var store = ScanStore()
    @State private var measure = MeasureState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .environment(measure)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            ScanView()
                .tabItem { Label("Scan", systemImage: "camera.metering.matrix") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "cube.transparent") }
        }
    }
}
