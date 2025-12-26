//
//  WaitingLogin.swift
//  Scroblebler
//
//  Created by Victor Gama on 25/11/2022.
//

import SwiftUI

struct WaitingLogin: View {
    enum Status {
        case generatingToken
        case waitingForLogin
        case finishingUp
    }
    @Binding var status: Status
    var onCancel: () -> ()
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Login on Last.fm")
                    .font(.headline)
                HStack(spacing: 10) {
                    ActivityIndicator()
                    switch status {
                    case .generatingToken:
                        Text("Preparing to Login...")
                    case .waitingForLogin:
                        Text("Waiting for login completion on your browser")
                    case .finishingUp:
                        Text("Finishing up...")
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .padding()
            Spacer()
        }
        .frame(minWidth: 500)
    }
}

struct WaitingLogin_Previews: PreviewProvider {
    static var previews: some View {
        WaitingLogin(status: .constant(.generatingToken), onCancel: {})
    }
}
