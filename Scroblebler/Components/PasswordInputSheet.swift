import SwiftUI

struct PasswordInputSheet: View {
    @Binding var password: String
    let username: String
    let onSubmit: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Enable Scrobble Deletion")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("To enable undo functionality for Last.fm, please enter your password:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                
                Text("Username: \(username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password (Cmd+V to paste):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    PasswordInputField(text: $password)
                        .frame(width: 280, height: 30)
                }
                
                Text("This enables web-based scrobble deletion. You can skip this and add it later.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            HStack(spacing: 12) {
                Button("Skip") {
                    onSkip()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Enable") {
                    onSubmit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(40)
        .frame(width: 350, height: 290)
    }
}
