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
    
    private var headerGradient: LinearGradient {
        switch defaults.mainServicePreference {
        case .listenbrainz:
            return LinearGradient(
                colors: [
                    Color(red: 245/255, green: 150/255, blue: 100/255),
                    Color(red: 255/255, green: 170/255, blue: 120/255),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .lastfm:
            return LinearGradient(
                colors: [
                    Color(red: 186/255, green: 0/255, blue: 0/255),
                    Color(red: 214/255, green: 10/255, blue: 10/255),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .librefm:
            return LinearGradient(
                colors: [
                    Color(red: 183/255, green: 65/255, blue: 78/255),
                    Color(red: 203/255, green: 85/255, blue: 98/255),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .none:
            return LinearGradient(
                colors: [
                    Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 61.0/100.0),
                    Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 89.0/100.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .center) {
            HStack {
                if let service = defaults.mainServicePreference {
                    let logoHeight: CGFloat = service == .lastfm ? 28 : 35
                    let verticalPadding: CGFloat = service == .lastfm ? 13.5 : 10
                    
                    serviceLogo(for: service)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(height: logoHeight)
                        .padding(.vertical, verticalPadding)
                } else {
                    Image("app-logo")
                        .resizable()
                        .antialiased(true)
                        .scaledToFit()
                        .frame(height: 55)
                }
                
                Spacer()
                
                if defaults.name != nil {
                    HStack(spacing: 12) {
                        if showProfileView {
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(defaults.name ?? "")
                                        .font(.system(size: 14, weight: .semibold))
                                    if defaults.pro ?? false {
                                        Text("PRO")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.red)
                                            .cornerRadius(2)
                                    }
                                }
                                
                                if let url = defaults.url {
                                    Button(action: {
                                        if let url = URL(string: url) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        Text("View on \(defaults.mainServicePreference?.displayName ?? "service")")
                                            .font(.system(size: 11))
                                            .foregroundColor(linkColor)
                                            .underline()
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .transition(.opacity)
                        } else {
                            HStack(spacing: 0) {
                                Text(defaults.name ?? "")
                                if defaults.pro ?? false {
                                    Text("PRO")
                                        .fontWeight(.light)
                                        .font(.system(size: 9))
                                        .offset(y: -5)
                                }
                            }
                            .transition(.opacity)
                        }
                        
                        Button(action: {
                            withAnimation {
                                showProfileView.toggle()
                            }
                        }) {
                            if let pictureData = defaults.picture,
                               let nsImage = NSImage(data: pictureData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .frame(width: 42, height: 42)
                                    .cornerRadius(4)
                            } else {
                                Image("avatar")
                                    .resizable()
                                    .frame(width: 42, height: 42)
                                    .cornerRadius(4)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .frame(width: 400, height: 55)
        .background(headerGradient)
    }
    
    private var linkColor: Color {
        switch defaults.mainServicePreference {
        case .lastfm:
            return Color(red: 255/255, green: 200/255, blue: 200/255)
        case .librefm:
            return Color.white
        case .listenbrainz:
            return Color(red: 255/255, green: 220/255, blue: 200/255)
        case .none:
            return Color.white
        }
    }
    
    private func serviceLogo(for service: ScrobbleService) -> Image {
        switch service {
        case .lastfm:
            return Image("as-logo")
        case .librefm:
            return Image("librefm-logo")
        case .listenbrainz:
            return Image("lb-logo")
        }
    }
}

struct Header_Previews: PreviewProvider {
    static var previews: some View {
        Header(showProfileView: .constant(false))
    }
}
