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
                .foregroundColor(isBlacklisted ? .red : .secondary)
                .font(.system(size: 11))
                .frame(width: 11, height: 11)
        }
        .buttonStyle(.borderless)
        .help(isBlacklisted ? "Un-blacklist Track" : "Blacklist Track")
    }
    
    private var isBlacklisted: Bool {
        defaults.isBlacklisted(artist: artist, track: track)
    }
}
