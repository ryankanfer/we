import SwiftUI

struct SplashView: View {
    let onDone: () -> Void
    @State private var overlap: Overlap = .apart

    var body: some View {
        VStack(spacing: 28) {
            InterlockMark(overlap: overlap, size: 96)
            Text("WE").font(.serif(28)).tracking(10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9)) { overlap = .interlocked }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { onDone() }
        }
    }
}

struct OnboardingView: View {
    let onDone: () -> Void
    @State private var step = 0

    var body: some View {
        VStack {
            TabView(selection: $step) {
                arrival.tag(0)
                howItWorks.tag(1)
                promise.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Capsule().fill(i == step ? Palette.ink.opacity(0.6) : Palette.ink.opacity(0.15))
                        .frame(width: i == step ? 20 : 4, height: 4)
                }
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .foregroundColor(Palette.ink)
    }

    private var arrival: some View {
        VStack(spacing: 0) {
            Spacer()
            InterlockMark(overlap: .touching, size: 84, breathing: true)
            Text("WE").font(.serif(34)).tracking(9).padding(.top, 28)
            Text("A quiet layer for the two of you.")
                .font(.serif(20)).multilineTextAlignment(.center).padding(.top, 16)
            Text("WE notices what may need attention, and helps you meet it together — without turning your relationship into work.")
                .font(.system(size: 15)).foregroundColor(Palette.faint)
                .multilineTextAlignment(.center).padding(.top, 12)
            Spacer()
            PrimaryButton(title: "Come in") { withAnimation { step = 1 } }.padding(.bottom, 8)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(spacing: 12) {
                InterlockMark(overlap: .interlocked, size: 34)
                Text("One shared place.").font(.serif(28))
            }
            Text("Not two accounts and a shared folder — one continuity, for both of you. WE keeps an eye on the life you share and surfaces only what’s worth your attention, seen through three lenses:")
                .font(.system(size: 15)).foregroundColor(Palette.faint).padding(.top, 14)
            VStack(alignment: .leading, spacing: 18) {
                lens("Today", "What needs the two of you right now.")
                lens("Life", "The life you’re building and running together.")
                lens("Us", "The two of you — time, closeness, attention.")
            }
            .padding(.top, 24)
            Spacer()
            PrimaryButton(title: "And one promise") { withAnimation { step = 2 } }.padding(.bottom, 8)
        }
    }

    private func lens(_ name: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle().fill(Palette.line).frame(width: 1, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.serif(18))
                Text(sub).font(.system(size: 14)).foregroundColor(Palette.faint)
            }
        }
    }

    private var promise: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("The promise.").font(.serif(28))
            VStack(alignment: .leading, spacing: 20) {
                ForEach(promiseLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 14) {
                        Circle().fill(Palette.ink.opacity(0.4)).frame(width: 4, height: 4).padding(.top, 9)
                        Text(line).font(.serif(17)).foregroundColor(Palette.ink.opacity(0.85))
                    }
                }
            }
            .padding(.top, 28)
            Spacer()
            PrimaryButton(title: "Let’s begin", action: onDone).padding(.bottom, 8)
        }
    }

    private let promiseLines = [
        "Some things stay yours until you both choose to open them — together.",
        "“Not now” is always safe. No one is told, and no one keeps count.",
        "WE describes patterns. It never diagnoses people, and it never scores you.",
        "The better things are, the quieter WE becomes.",
    ]
}
