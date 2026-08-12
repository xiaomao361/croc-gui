import AppKit
import SwiftUI

final class CrocAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: TransferStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.phase.isRunning == true else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "A transfer is still running"
        alert.informativeText = "Finish or cancel the transfer before quitting croc."
        alert.addButton(withTitle: "Keep transferring")
        let cancelButton = alert.addButton(withTitle: "Cancel transfer")
        cancelButton.hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            store?.cancel()
        }
        return .terminateCancel
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
                .preferredColorScheme(.light)
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)
    }
}
