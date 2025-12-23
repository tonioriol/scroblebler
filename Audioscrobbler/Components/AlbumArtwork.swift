import SwiftUI

struct AlbumArtwork: View {
    let imageUrl: String?
    let imageData: Data?
    let size: CGFloat
    
    @State private var artwork: Data?
    
    init(imageUrl: String?, size: CGFloat) {
        self.imageUrl = imageUrl
        self.imageData = nil
        self.size = size
    }
    
    init(imageData: Data?, size: CGFloat) {
        self.imageUrl = nil
        self.imageData = imageData
        self.size = size
    }
    
    func artworkImage() -> Image {
        if let artData = imageData ?? artwork, let img = NSImage(data: artData) {
            return Image(nsImage: img)
        }
        return Image("nocover")
    }
    
    func loadArtwork() async {
        guard let imageUrl = imageUrl, let url = URL(string: imageUrl) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run {
                artwork = data
            }
        } catch {
            // Silently fail - will show nocover image
        }
    }
    
    var body: some View {
        artworkImage()
            .resizable()
            .cornerRadius(3)
            .frame(width: size, height: size)
            .onAppear {
                if imageUrl != nil {
                    Task {
                        await loadArtwork()
                    }
                }
            }
    }
}
