//
//  TokenInputSheet.swift
//  Audioscrobbler
//
//  Created by Audioscrobbler on 25/12/2024.
//

import SwiftUI
import AppKit

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

struct TokenInputSheet: View {
    @Binding var token: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Enter ListenBrainz Token")
                .font(.headline)
            
            Text("Get your personal token from:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: {
                if let url = URL(string: "https://listenbrainz.org/settings/") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("https://listenbrainz.org/settings/")
                    .font(.caption)
            }
            .buttonStyle(.link)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Token (Cmd+V to paste):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TokenInputField(text: $token)
                    .frame(width: 280, height: 30)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Submit") {
                    onSubmit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(40)
        .frame(width: 380, height: 240)
    }
}
