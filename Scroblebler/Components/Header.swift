//
//  Header.swift
//  Scroblebler
//
//  Created by Victor Gama on 24/11/2022.
//

import SwiftUI

struct Header: View {
    @EnvironmentObject var defaults: Defaults
    @Binding var showProfileView: Bool
    @State var showSignoutScreen = false
    
    var body: some View {
        VStack(alignment: .center) {
            HStack(alignment: .center) {
                Image("app-logo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 55)
                Spacer()
                if defaults.name != nil {
                    HStack {
                        VStack(spacing: 2) {
                            HStack(spacing: 0) {
                                Text(defaults.name ?? "")
                                if defaults.pro ?? false {
                                    Text("PRO")
                                        .fontWeight(.light)
                                        .font(.system(size: 9))
                                        .offset(y: -5)
                                }
                            }
                            Button("Sign Out") { showSignoutScreen = true }
                                .buttonStyle(.link)
                                .foregroundColor(.white.opacity(0.7))
                                .alert(isPresented: $showSignoutScreen) {
                                    Alert(title: Text("Signing out will stop scrobbling on this account and remove all local data. Do you wish to continue?"),
                                          primaryButton: .cancel(),
                                          secondaryButton: .default(Text("Continue")) {
                                        defaults.reset()
                                    })

                                }
                        }
                        Button(action: { showProfileView = true }) {
                            if defaults.picture == nil {
                                Image("avatar")
                                    .resizable()
                                    .frame(width: 42, height: 42)
                                    .cornerRadius(4)
                            } else {
                                Image(nsImage: NSImage(data: defaults.picture!) ?? NSImage(named: "avatar")!)
                                    .resizable()
                                    .frame(width: 42, height: 42)
                                    .cornerRadius(4)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }.padding()
        }
        .frame(maxHeight: 55)
        .background(LinearGradient(colors: [
            Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 61.0/100.0),
            Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 89.0/100.0),
        ], startPoint: .top, endPoint: .bottom))
    }
}

struct Header_Previews: PreviewProvider {
    static var previews: some View {
        Header(showProfileView: .constant(false))
    }
}
