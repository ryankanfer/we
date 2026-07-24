import SwiftUI

enum Overlap { case apart, touching, interlocked }

/// WE's one recurring mark: two rings whose overlap expresses the state between
/// two people. State never relies on it alone — it always sits beside a label.
struct InterlockMark: View {
    var overlap: Overlap = .apart
    var size: CGFloat = 40
    var breathing: Bool = false
    @State private var pulse = false

    var body: some View {
        let r = size * 0.28
        let gap: CGFloat = overlap == .apart ? r * 2.6 : overlap == .touching ? r * 2.0 : r * 1.15
        ZStack {
            Circle().stroke(Palette.burgundy, lineWidth: size * 0.035)
                .frame(width: r * 2, height: r * 2).offset(x: -gap / 2)
            Circle().stroke(Palette.sage, lineWidth: size * 0.035)
                .frame(width: r * 2, height: r * 2).offset(x: gap / 2)
        }
        .frame(width: size, height: size)
        .scaleEffect(breathing && pulse ? 1.05 : 1.0)
        .opacity(breathing && pulse ? 1.0 : 0.9)
        .animation(breathing ? .easeInOut(duration: 2.2).repeatForever(autoreverses: true) : .default, value: pulse)
        .onAppear { if breathing { pulse = true } }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(1.6)
            .foregroundColor(Palette.faint)
    }
}

struct Dot: View {
    let hue: Hue
    var body: some View { Circle().fill(hue.color).frame(width: 8, height: 8) }
}

struct Avatar: View {
    let member: Member?
    var size: CGFloat = 28
    var body: some View {
        Text(String((member?.name ?? "·").prefix(1)))
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundColor((member?.hue ?? .burgundy).color)
            .frame(width: size, height: size)
            .background((member?.hue ?? .burgundy).soft)
            .clipShape(Circle())
    }
}

struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Palette.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Palette.ink)
                .clipShape(Capsule())
        }
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

struct QuietButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Palette.faint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }
}

/// A person's name in their relational hue (colour + text, never colour alone).
struct PersonChip: View {
    let member: Member?
    var suffix: String = ""
    var body: some View {
        HStack(spacing: 6) {
            Dot(hue: member?.hue ?? .burgundy)
            Text("\(member?.name ?? "Partner")\(suffix.isEmpty ? "" : " \(suffix)")")
                .font(.system(size: 12))
                .foregroundColor(Palette.faint)
        }
    }
}
