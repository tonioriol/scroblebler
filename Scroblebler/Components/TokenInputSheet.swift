//
//  TokenInputSheet.swift
//  Scroblebler
//
//  Created by Scroblebler on 25/12/2024.
//

import SwiftUI

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
