import SwiftUI

struct PlayingItemView: View {
    @EnvironmentObject var webService: WebService
    @EnvironmentObject var defaults: Defaults
    @Binding var track: Track?
    @Binding var currentPosition: Double?

    func formatDuration(_ value: Double) -> String {
        let hours = value / 3600
        let minutes = Int(value.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(value.truncatingRemainder(dividingBy: 60))

        if hours >= 1 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds);
        } else if minutes >= 1 {
            return String(format: "%02d:%02d", minutes, seconds);
        } else {
            return String(format: "00:%02d", seconds);
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top) {
                AlbumArtwork(imageData: track?.artwork, size: 92)
                VStack(alignment: .leading, spacing: 3) {
                    Link(track!.name, destination: .lastFmTrack(artist: track!.artist, track: track!.name))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.lastFmRed)
                        .padding(.trailing, 28)
                    HStack(spacing: 3) {
                        Text("by")
                        Link(track!.artist, destination: .lastFmArtist(track!.artist))
                            .foregroundColor(.lastFmRed)
                    }
                    HStack(spacing: 3) {
                        Text("on")
                        Link(track!.album, destination: .lastFmAlbum(artist: track!.artist, album: track!.album))
                            .foregroundColor(.lastFmRed)
                    }
                    HStack(spacing: 3) {
                        Text("released")
                        Text("\(String(format: "%04d", track!.year))")
                    }
                    HStack(spacing: 8) {
                        Text(formatDuration(currentPosition!))
                            .font(.caption)
                        ProgressBar(value: currentPosition!, maxValue: track!.length)
                            .frame(height: 8)
                        Text(formatDuration(track!.length))
                            .font(.caption)
                    }
                }
            }
            LoveButton(loved: Binding(
                get: { track?.loved ?? false },
                set: { track?.loved = $0 }
            ), artist: track!.artist, trackName: track!.name, fontSize: 12)
            .padding(.top, 4)
        }
        .padding()
        .animation(nil)
    }
}

struct PlayingItemView_Previews: PreviewProvider {
    static var previews: some View {
        PlayingItemView(track: .constant(.init(artist: "Alexisonfire", album: "Watch Out!", name: "It Was Fear Of Myself That Made Me Odd", year: 2004, length: 123.10293, artwork: nil, loved: true, startedAt: 0)), currentPosition: .constant(61.5))
    }
}
