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
    @State private var timer: Timer?
    @State private var direction: CGFloat = 1
    @State private var pauseUntil: Date?
    
    private let speed: CGFloat = 25
    private let pauseDuration: TimeInterval = 1.0
    private let fps: TimeInterval = 1.0 / 60.0
    
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
            .background(GeometryReader { geo in
                Color.clear.preference(key: WidthPreferenceKey.self, value: geo.size.width)
            })
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
                if hovering && shouldAnimate {
                    startScrolling()
                } else {
                    stopScrolling()
                }
            }
            .help(shouldAnimate ? text : "")
    }
    
    private func measureTextWidth() {
        let weight: NSFont.Weight = switch fontWeight {
            case .ultraLight: .ultraLight
            case .thin: .thin
            case .light: .light
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            case .black: .black
            default: .regular
        }
        
        let nsFont = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let size = (text as NSString).size(withAttributes: [.font: nsFont])
        textWidth = size.width
    }
    
    private func startScrolling() {
        guard timer == nil else { return }
        
        if offset == 0 || offset == textWidth - containerWidth {
            pauseUntil = Date().addingTimeInterval(pauseDuration)
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: fps, repeats: true) { _ in
            if let pause = pauseUntil, Date() < pause { return }
            pauseUntil = nil
            
            let maxOffset = textWidth - containerWidth
            offset += speed * CGFloat(fps) * direction
            
            if offset >= maxOffset {
                offset = maxOffset
                direction = -1
                pauseUntil = Date().addingTimeInterval(pauseDuration)
            } else if offset <= 0 {
                offset = 0
                direction = 1
                pauseUntil = Date().addingTimeInterval(pauseDuration)
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
