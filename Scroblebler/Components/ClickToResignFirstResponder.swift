import AppKit
import SwiftUI

/// Clears focus (first responder) when clicking on non-interactive areas.
///
/// This fixes the macOS behavior where clicking on blank SwiftUI areas does not
/// change the first responder, so `NSTextField` focus can get "stuck".
struct ClickToResignFirstResponder: NSViewRepresentable {
    func makeNSView(context: Context) -> MonitorView {
        MonitorView()
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        // no-op
    }

    final class MonitorView: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitorIfNeeded()
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window else { return event }
                guard event.window === window else { return event }

                // Only intervene when a text field is actively editing.
                // This avoids interfering with normal button clicks / playback controls.
                guard window.firstResponder is NSTextView else {
                    return event
                }

                // hitTest expects the point in the contentView's coordinate space.
                let point = window.contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
                let hit = window.contentView?.hitTest(point)

                // If the click is going into another text input/control, don't force resign.
                if Self.isTextInput(hit) {
                    return event
                }

                // Defer to avoid interfering with the current click's normal dispatch.
                DispatchQueue.main.async {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }

        private static func isTextInput(_ view: NSView?) -> Bool {
            var current = view
            while let v = current {
                if v is NSTextField { return true }
                if v is NSTextView { return true }
                current = v.superview
            }
            return false
        }
    }
}
