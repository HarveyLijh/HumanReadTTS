import SwiftUI

struct AppScene: Scene {
    var body: some Scene {
        WindowGroup("Rhea") {
            DropTargetView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 600)
    }
}
