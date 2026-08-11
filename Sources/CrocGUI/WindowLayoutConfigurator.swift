import AppKit
import SwiftUI

struct WindowLayoutConfigurator: NSViewRepresentable {
    private let migrationKey = "didApplyCompactWindowLayoutV2"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window,
                  !UserDefaults.standard.bool(forKey: migrationKey) else { return }

            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.setContentSize(NSSize(width: 900, height: 620))
            window.setFrameTopLeftPoint(topLeft)
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
