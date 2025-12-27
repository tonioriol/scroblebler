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
        guard let imageUrl = imageUrl else { return }
        
        // Check cache first
        if let cachedData = await MainActor.run(body: { ImageCache.shared.get(imageUrl) }) {
            await MainActor.run {
                artwork = cachedData
            }
            return
        }
        
        // Not in cache - load from network
        guard let url = URL(string: imageUrl) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run {
                artwork = data
                ImageCache.shared.set(imageUrl, data: data)
            }
        } catch {
            // Failed to load - don't cache failures, just show nocover
        }
    }
    
    var body: some View {
        artworkImage()
            .resizable()
            .cornerRadius(3)
            .frame(width: size, height: size)
            .onAppear {
                Task {
                    await loadArtwork()
                }
            }
            .onChange(of: imageUrl) { _ in
                Task {
                    await loadArtwork()
                }
            }
    }
}
