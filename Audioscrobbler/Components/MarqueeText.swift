import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isHovered = false
    @State private var timer: Timer?
    @State private var isScrollingForward = true
    @State private var isPaused = false
    @State private var pauseEndTime: Date?
    
    // Fixed scrolling speed in points per second
    private let scrollSpeed: CGFloat = 25
    // Pause duration at edges in seconds
    private let pauseDuration: Double = 1.0
    // Update interval in seconds (higher = smoother but more CPU)
    private let updateInterval: TimeInterval = 0.016 // ~60 FPS
    
    var shouldAnimate: Bool {
        textWidth > containerWidth && containerWidth > 0
    }
    
    init(text: String, font: Font, foregroundColor: Color, fontSize: CGFloat = 13, fontWeight: Font.Weight = .regular) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
        self.fontSize = fontSize
        self.fontWeight = fontWeight
    }
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(shouldAnimate ? .clear : foregroundColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: WidthPreferenceKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(WidthPreferenceKey.self) { width in
                containerWidth = width
                measureTextWidth()
            }
            .overlay(
                Group {
                    if shouldAnimate {
                        GeometryReader { geo in
                            Text(text)
                                .font(font)
                                .foregroundColor(foregroundColor)
                                .fixedSize()
                                .offset(x: -offset)
                        }
                        .clipped()
                    }
                }
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering && shouldAnimate {
                    startScrolling()
                } else {
                    stopScrolling()
                }
            }
            .help(shouldAnimate ? text : "")
    }
    
    private func measureTextWidth() {
        let weight: NSFont.Weight = {
            switch fontWeight {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            default: return .regular
            }
        }()
        
        let nsFont = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [.font: nsFont]
        let size = (text as NSString).size(withAttributes: attributes)
        textWidth = size.width
    }
    
    private func startScrolling() {
        // If already scrolling, don't restart
        guard timer == nil else { return }
        
        // Start with a pause if we're at the beginning or end
        if offset == 0 || offset == textWidth - containerWidth {
            isPaused = true
            pauseEndTime = Date().addingTimeInterval(pauseDuration)
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            guard isHovered else { return }
            
            let now = Date()
            let maxOffset = textWidth - containerWidth
            
            // Handle pause
            if isPaused {
                if let endTime = pauseEndTime, now >= endTime {
                    isPaused = false
                    pauseEndTime = nil
                }
                return
            }
            
            // Calculate movement
            let movement = scrollSpeed * CGFloat(updateInterval)
            
            if isScrollingForward {
                offset += movement
                
                if offset >= maxOffset {
                    offset = maxOffset
                    isScrollingForward = false
                    isPaused = true
                    pauseEndTime = now.addingTimeInterval(pauseDuration)
                }
            } else {
                offset -= movement
                
                if offset <= 0 {
                    offset = 0
                    isScrollingForward = true
                    isPaused = true
                    pauseEndTime = now.addingTimeInterval(pauseDuration)
                }
            }
        }
    }
    
    private func stopScrolling() {
        timer?.invalidate()
        timer = nil
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
