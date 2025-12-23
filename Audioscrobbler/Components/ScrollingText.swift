import SwiftUI

struct ScrollingText: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
