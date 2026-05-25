import SwiftUI
import AppKit

/// Bridges to the underlying NSWindow so SwiftUI views can adopt the
/// hidden-titlebar, full-content-view-area look that boutique macOS apps
/// favour. Inserts on first appearance and is otherwise inert.
struct WindowConfigurator: NSViewRepresentable {
    var hideTitle: Bool = false
    var movableByBackground: Bool = true

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { [weak v] in
            guard let window = v?.window else { return }
            if hideTitle {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = movableByBackground
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
