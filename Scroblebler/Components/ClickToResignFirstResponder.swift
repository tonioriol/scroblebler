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

                let hit = window.contentView?.hitTest(event.locationInWindow)
                if Self.isInteractive(hit) {
                    return event
                }

                window.makeFirstResponder(nil)
                return event
            }
        }

        private static func isInteractive(_ view: NSView?) -> Bool {
            var current = view
            while let v = current {
                // Buttons, text fields, segmented controls, scrollers, etc.
                if v is NSControl { return true }
                // NSTextView covers some SwiftUI/AppKit bridge cases.
                if v is NSTextView { return true }
                current = v.superview
            }
            return false
        }
    }
}

