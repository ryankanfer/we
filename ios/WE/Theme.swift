import SwiftUI

/// WE's visual language — warm cream canvas, burgundy + sage as the two partners'
/// relational identities, editorial serif for observations, restrained sans for
/// actions. Mirrors the web build's tokens.
enum Palette {
    static let cream = Color(hex: 0xF6F1E7)
    static let card = Color(hex: 0xFCFAF4)
    static let ink = Color(hex: 0x27211A)
    static let faint = Color(hex: 0x8B8172)
    static let line = Color(hex: 0xE3DBC9)
    static let burgundy = Color(hex: 0x7D3C43)
    static let burgundySoft = Color(hex: 0xF0E4E2)
    static let sage = Color(hex: 0x5F6B52)
    static let sageSoft = Color(hex: 0xE9ECDF)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Font {
    /// Editorial serif for meaningful observations.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// A hue token resolved to its colors.
enum Hue: String, Codable {
    case burgundy, sage

    var color: Color { self == .sage ? Palette.sage : Palette.burgundy }
    var soft: Color { self == .sage ? Palette.sageSoft : Palette.burgundySoft }
}

struct CardBackground: ViewModifier {
    var fill: Color = Palette.card
    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
    }
}

extension View {
    func weCard(_ fill: Color = Palette.card) -> some View { modifier(CardBackground(fill: fill)) }
}
