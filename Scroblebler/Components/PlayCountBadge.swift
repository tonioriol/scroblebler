import SwiftUI

struct PlayCountBadge: View {
    let playCount: Int?
    let fontSize: CGFloat
    
    var body: some View {
        Group {
            if let count = playCount {
                HStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: fontSize))
                        .foregroundColor(.secondary)
                    Text("\(formatPlaycount(count))")
                        .font(.system(size: fontSize - 1))
                        .foregroundColor(.secondary)
                }
                .help(count == 1 ? "You've played this track 1 time" : "You've played this track \(count) times")
            }
        }
    }
    
    func formatPlaycount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
}
