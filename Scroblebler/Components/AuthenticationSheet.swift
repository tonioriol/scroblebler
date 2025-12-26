//
//  AuthenticationSheet.swift
//  Scroblebler
//
//  Created by Scroblebler on 24/12/2024.
//

import SwiftUI

struct AuthenticationSheet: View {
    let service: ScrobbleService
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Authenticating with \(service.displayName)")
                .font(.headline)
            
            ProgressView()
                .progressViewStyle(.circular)
            
            Text("Complete authorization in your browser, then return here")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(40)
        .frame(width: 300, height: 200)
    }
}
