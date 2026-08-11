import AppKit
import SwiftUI

final class CrocAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CrocGUIApp: App {
    @NSApplicationDelegateAdaptor(CrocAppDelegate.self) private var appDelegate
    @StateObject private var store = TransferStore()

    var body: some Scene {
        Window("croc", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)
    }
}
