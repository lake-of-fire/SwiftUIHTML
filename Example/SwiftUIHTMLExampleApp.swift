//  Copyright © 2025 PRND. All rights reserved.

import SwiftUI



@main
struct SwiftUIHTMLExampleApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private struct RootView: View {
    private let stressOnly = ProcessInfo.processInfo.environment["SWIFTUIHTML_STRESS_ONLY"] == "1"

    var body: some View {
        if stressOnly {
            NavigationView {
                SyntheticStressSample()
            }
        } else {
            ContentView()
        }
    }
}
