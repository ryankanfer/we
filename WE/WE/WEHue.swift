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

    static let personalStorageKey = "personalHue"
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
        switch self {
        case .burgundy:
            Color(red: 0.49, green: 0.235, blue: 0.263)
        case .sage:
            Color(red: 0.373, green: 0.42, blue: 0.322)
        case .ember:
            Color(red: 0.78, green: 0.31, blue: 0.22)
        case .tide:
            Color(red: 0.16, green: 0.48, blue: 0.58)
        case .plum:
            Color(red: 0.49, green: 0.29, blue: 0.54)
        case .clay:
            Color(red: 0.68, green: 0.45, blue: 0.34)
        case .pearl:
            Color(red: 0.89, green: 0.84, blue: 0.74)
        case .mist:
            Color(red: 0.66, green: 0.76, blue: 0.82)
        case .blush:
            Color(red: 0.85, green: 0.62, blue: 0.64)
        case .celadon:
            Color(red: 0.68, green: 0.78, blue: 0.68)
        }
    }

    /// Hues bright enough that white text placed over them stops being legible.
    var isLight: Bool {
        switch self {
        case .pearl, .mist, .blush, .celadon:
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
        switch self {
        case .pearl:
            Color(red: 0.46, green: 0.38, blue: 0.27)
        case .mist:
            Color(red: 0.31, green: 0.46, blue: 0.57)
        case .blush:
            Color(red: 0.56, green: 0.32, blue: 0.36)
        case .celadon:
            Color(red: 0.32, green: 0.47, blue: 0.36)
        default:
            color
        }
    }

    static func stored(_ rawValue: String) -> WEHue {
        WEHue(rawValue: rawValue) ?? .burgundy
    }
}

extension Color {
    static let weCinematicInk = Color(
        red: 0.153,
        green: 0.129,
        blue: 0.102
    )
}
