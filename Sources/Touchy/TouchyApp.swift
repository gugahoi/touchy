import SwiftUI

@main
struct TouchyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Touchy", systemImage: "hand.point.up.left") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
