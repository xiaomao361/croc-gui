import AppKit
import SwiftUI

struct NativeFileDropTarget: NSViewRepresentable {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        context.coordinator.parent = self
        nsView.isDropEnabled = isEnabled
    }

    @MainActor
    final class Coordinator {
        var parent: NativeFileDropTarget

        init(parent: NativeFileDropTarget) {
            self.parent = parent
        }

        func setTargeted(_ targeted: Bool) {
            parent.isTargeted = targeted
        }

        func accept(_ urls: [URL]) -> Bool {
            parent.onDrop(urls)
        }
    }

    @MainActor
    final class DropView: NSView {
        weak var coordinator: Coordinator?
        var isDropEnabled = true

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard isDropEnabled, !Self.fileURLs(from: sender.draggingPasteboard).isEmpty else {
                return []
            }
            coordinator?.setTargeted(true)
            return .copy
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard isDropEnabled, !Self.fileURLs(from: sender.draggingPasteboard).isEmpty else {
                coordinator?.setTargeted(false)
                return []
            }
            return .copy
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            coordinator?.setTargeted(false)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            coordinator?.setTargeted(false)
            guard isDropEnabled else { return false }
            return coordinator?.accept(Self.fileURLs(from: sender.draggingPasteboard)) ?? false
        }

        static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
            let objects = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) ?? []

            return objects.compactMap { object in
                let url: URL?
                if let value = object as? URL {
                    url = value
                } else if let value = object as? NSURL {
                    url = value as URL
                } else {
                    url = nil
                }

                guard let url, url.isFileURL else { return nil }
                return url.standardizedFileURL
            }
        }
    }
}
