import SwiftUI
import AppKit

// MARK: - Pasteable Text Fields

class PasteableTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                if let clipboardString = NSPasteboard.general.string(forType: .string) {
                    self.stringValue = clipboardString
                    self.window?.makeFirstResponder(self)
                    NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: self)
                }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

class PasteableSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                if let clipboardString = NSPasteboard.general.string(forType: .string) {
                    self.stringValue = clipboardString
                    self.window?.makeFirstResponder(self)
                    NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: self)
                }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - SwiftUI Wrappers

struct TokenInputField: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> PasteableTextField {
        let textField = PasteableTextField()
        textField.placeholderString = "Paste (Cmd+V) or type your token here"
        textField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.delegate = context.coordinator
        
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }
        
        return textField
    }
    
    func updateNSView(_ nsView: PasteableTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TokenInputField
        
        init(_ parent: TokenInputField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}

struct PasswordInputField: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> PasteableSecureTextField {
        let textField = PasteableSecureTextField()
        textField.placeholderString = "Paste (Cmd+V) or type your password"
        textField.delegate = context.coordinator
        
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }
        
        return textField
    }
    
    func updateNSView(_ nsView: PasteableSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PasswordInputField
        
        init(_ parent: PasswordInputField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}
