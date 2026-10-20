import SwiftUI

@main
struct LocalDiffApp: App {
    var body: some Scene {
        Window("LocalDiff", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1400, height: 900)
        .restorationBehavior(.disabled)
    }
}
