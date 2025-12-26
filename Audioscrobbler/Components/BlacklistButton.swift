import SwiftUI

struct BlacklistButton: View {
    @EnvironmentObject var defaults: Defaults
    
    let artist: String
    let track: String
    
    var body: some View {
        Button {
            defaults.toggleBlacklist(artist: artist, track: track)
        } label: {
            Image(systemName: "nosign")
                .resizable()
                .scaledToFit()
                .foregroundColor(isBlacklisted ? .red : .secondary)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isBlacklisted ? "Un-blacklist Track" : "Blacklist Track")
    }
    
    private var isBlacklisted: Bool {
        defaults.isBlacklisted(artist: artist, track: track)
    }
}
