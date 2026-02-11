import SwiftUI

/// macOS 11-compatible focus-aware text field.
///
/// SwiftUI's `FocusState` requires macOS 12+, but the app targets macOS 11.
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onFocusChange: onFocusChange)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.delegate = context.coordinator

        // Match the old `.textFieldStyle(.plain)` usage.
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var text: Binding<String>
        private var onFocusChange: (Bool) -> Void

        init(text: Binding<String>, onFocusChange: @escaping (Bool) -> Void) {
            self.text = text
            self.onFocusChange = onFocusChange
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            onFocusChange(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            onFocusChange(false)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

