import AppKit
import SwiftUI

struct WindowLayoutConfigurator: NSViewRepresentable {
    let preventsClosing: Bool
    private let migrationKey = "didApplyCompactWindowLayoutV2"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configureCloseButton(in: window)
            guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.setContentSize(NSSize(width: 900, height: 620))
            window.setFrameTopLeftPoint(topLeft)
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            configureCloseButton(in: window)
        }
    }

    private func configureCloseButton(in window: NSWindow) {
        let button = window.standardWindowButton(.closeButton)
        button?.isEnabled = !preventsClosing
        button?.toolTip = preventsClosing
            ? "Finish or cancel the transfer before closing this window."
            : nil
    }
}
