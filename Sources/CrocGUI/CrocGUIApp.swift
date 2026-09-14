import AppKit
import SwiftUI

final class CrocAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: TransferStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.isBusy == true else { return .terminateNow }

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
                .frame(minWidth: 520, minHeight: 400)
                .preferredColorScheme(.light)
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 520, height: 440)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
    }
}
