import SwiftUI

enum WEHue: String, CaseIterable, Identifiable {
    case burgundy
    case sage
    case ember
    case tide
    case plum
    case clay
    case pearl
    case mist
    case blush
    case celadon

    static let partnerDefault: WEHue = .sage
    static let pickerOrder: [WEHue] = [
        .pearl,
        .mist,
        .tide,
        .sage,
        .burgundy,
        .plum,
        .blush,
        .ember,
        .clay,
        .celadon
    ]

    var id: String { rawValue }

    var name: String {
        switch self {
        case .burgundy: "Burgundy"
        case .sage: "Sage"
        case .ember: "Ember"
        case .tide: "Tide"
        case .plum: "Plum"
        case .clay: "Clay"
        case .pearl: "Pearl"
        case .mist: "Mist"
        case .blush: "Blush"
        case .celadon: "Celadon"
        }
    }

    var color: Color {
        let components = colorComponents
        return Color(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }

    var colorComponents: (red: Double, green: Double, blue: Double) {
        switch self {
        case .burgundy:
            (0.49, 0.235, 0.263)
        case .sage:
            (0.373, 0.42, 0.322)
        case .ember:
            (0.78, 0.31, 0.22)
        case .tide:
            (0.16, 0.48, 0.58)
        case .plum:
            (0.49, 0.29, 0.54)
        case .clay:
            (0.68, 0.45, 0.34)
        case .pearl:
            (0.89, 0.84, 0.74)
        case .mist:
            (0.66, 0.76, 0.82)
        case .blush:
            (0.85, 0.62, 0.64)
        case .celadon:
            (0.68, 0.78, 0.68)
        }
    }

    /// Hues bright enough that white text placed over them stops being legible.
    var isLight: Bool {
        switch self {
        case .clay, .pearl, .mist, .blush, .celadon:
            true
        default:
            false
        }
    }

    /// The hue as it should appear behind white text — light hues are
    /// substituted for their deepened control tone so contrast holds.
    var atmosphereColor: Color {
        isLight ? controlColor : color
    }

    var controlColor: Color {
        let components = controlComponents
        return Color(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }

    var controlComponents: (red: Double, green: Double, blue: Double) {
        switch self {
        case .clay:
            (0.56, 0.34, 0.25)
        case .pearl:
            (0.46, 0.38, 0.27)
        case .mist:
            (0.31, 0.46, 0.57)
        case .blush:
            (0.56, 0.32, 0.36)
        case .celadon:
            (0.32, 0.47, 0.36)
        default:
            colorComponents
        }
    }

}

extension WEHue {
    init(_ hue: MemberHue) {
        self = WEHue(rawValue: hue.rawValue) ?? .burgundy
    }

    var memberHue: MemberHue {
        MemberHue(rawValue: rawValue) ?? .burgundy
    }
}

extension Color {
    static let weCinematicInk = Color(
        red: 0.153,
        green: 0.129,
        blue: 0.102
    )
}
