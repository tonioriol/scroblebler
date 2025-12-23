import SwiftUI

struct ScrollingText: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    
    @State private var animate = false
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
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
                                .offset(x: animate ? -(textWidth - containerWidth) : 0)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        let distance = textWidth - containerWidth
                                        let duration = Double(distance / 30)
                                        withAnimation(
                                            .easeInOut(duration: duration)
                                            .repeatForever(autoreverses: true)
                                        ) {
                                            animate = true
                                        }
                                    }
                                }
                        }
                        .clipped()
                    }
                }
            )
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
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
