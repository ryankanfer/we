import SwiftUI

/// The first run.
///
/// The Living Confluence Promise narrated three commitments over three slides.
/// This replaces it. Nothing here is described that the person does not do
/// with their own hands: they write the private line, they feel the boundary
/// refuse to let it cross, they meet the second tap they cannot reach, and
/// they set what the shared field is allowed to notice. The promises are the
/// same promises. They are demonstrated instead of announced.
///
/// The walkthrough is deliberately incomplete on purpose: the partner's side of
/// the field stays dark the whole way through, because it is. It fills when the
/// partner actually arrives, in `PartnerArrivalCeremony`, and not before.
struct ThresholdWalkthrough: View {
    enum Mode {
        /// Before an account exists. Choices are held on device and delivered
        /// once the two people are paired.
        case firstRun
        /// Replayed from Profile by someone already inside. Nothing is stored.
        case replay
    }

    var mode: Mode = .firstRun
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var lineIsFocused: Bool

    @State private var beat: Beat = .refusal
    @State private var privateLine = ""
    @State private var signals = ThresholdIntent.defaultSignals
    @State private var crossAttempts = 0
    @State private var dragOffset: CGSize = .zero
    @State private var yourTapLanded = false
    @State private var hasCrossed = false
    @State private var hapticTrigger = 0
    @State private var refusalTrigger = 0

    var body: some View {
        ZStack {
            Color.weCinematicInk.ignoresSafeArea()
            field
            scrim

            VStack(alignment: .leading, spacing: 0) {
                topBar
                Spacer(minLength: 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heading
                        stage
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                action
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .sensoryFeedback(.warning, trigger: refusalTrigger)
        .animation(settle(0.5), value: beat)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", beat.index + 1))
                .foregroundStyle(.white.opacity(0.42))
            WESectionLabel(beat.label)
            Spacer()
            Button(beat == .threshold ? "Close" : "Skip") { finish() }
                .font(.weCaption)
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.7))
                .frame(minHeight: 44)
                .accessibilityHint("Leaves the walkthrough. You can replay it from Profile.")
        }
        .font(.weCaption)
        .tracking(1.4)
        .padding(.top, 10)
    }

    /// The person's own side, alive. The partner's side, dark, all the way
    /// through: `connection` never leaves the low end of its range here.
    private var field: some View {
        WEConfluenceForm(
            personalHue: .burgundy,
            partnerHue: .sage,
            connection: connection
        )
        .opacity(0.72)
        .scaleEffect(1.2)
        .offset(x: dragOffset.width * 0.1, y: dragOffset.height * 0.1)
        .animation(settle(0.9), value: connection)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var scrim: some View {
        LinearGradient(
            colors: [
                Color.weCinematicInk.opacity(0.82),
                Color.weCinematicInk.opacity(0.36),
                Color.weCinematicInk.opacity(0.92),
                Color.weCinematicInk.opacity(0.99),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(beat.title)
                .font(.weLargeTitle)
                .foregroundStyle(.white)
            Text(beat.detail)
                .font(.weBody)
                .foregroundStyle(.white.opacity(0.64))
                .frame(maxWidth: 340, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(beat)
        .transition(.opacity)
    }

    // MARK: - Beats

    @ViewBuilder
    private var stage: some View {
        switch beat {
        case .refusal: refusalStage
        case .yourSide: yourSideStage
        case .boundary: boundaryStage
        case .bothHands: bothHandsStage
        case .signals: signalsStage
        case .threshold: thresholdStage
        }
    }

    /// Opening on what WE refuses to be is the fastest honest way to say what
    /// it is. It also sets the expectation that nothing here is measuring them.
    private var refusalStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.refusals, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("NO")
                        .font(.weCaption)
                        .tracking(1.6)
                        .foregroundStyle(WEHue.burgundy.controlColor)
                        .frame(width: 26, alignment: .leading)
                    Text(line)
                        .font(.weTitle)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
    }

    private var yourSideStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "",
                text: $privateLine,
                prompt: Text("Something on your mind tonight"),
                axis: .vertical
            )
            .lineLimit(2...5)
            .font(.weTitle)
            .foregroundStyle(.white)
            .tint(WEHue.burgundy.controlColor)
            .focused($lineIsFocused)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.14))
                    )
            )
            .accessibilityLabel("Your private line")
            .accessibilityIdentifier("thresholdPrivateLine")

            Label(
                mode == .replay
                    ? "In first use this line is kept on the phone until you pair."
                    : "This stays on this phone until you and your partner are paired. It has not been sent anywhere.",
                systemImage: "lock"
            )
            .font(.weCaption)
            .foregroundStyle(.white.opacity(0.52))
        }
        .onAppear { if !voiceOverEnabled { lineIsFocused = true } }
    }

    /// The trust model, in the hand. The line will not cross, and the refusal
    /// is felt before it is explained.
    private var boundaryStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [5, 6])
                    )
                    .foregroundStyle(.white.opacity(0.22))
                    .frame(height: 132)

                HStack(spacing: 0) {
                    carriedLine
                        .offset(x: max(dragOffset.width, 0))
                        .gesture(crossGesture)
                        .accessibilityLabel("Your private line")
                        .accessibilityHint("Drag it toward your partner's side")
                    Spacer(minLength: 0)
                }
                .padding(14)

                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Circle()
                            .strokeBorder(.white.opacity(0.2))
                            .frame(width: 34, height: 34)
                        Text("THEIR SIDE")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.34))
                    }
                    .padding(.trailing, 18)
                }
            }

            Text(crossAttempts == 0
                 ? "Try to push it across."
                 : "It will not go. Not by accident, not by insistence, not by you.")
                .font(.weBody)
                .foregroundStyle(
                    crossAttempts == 0
                        ? .white.opacity(0.5)
                        : WEHue.burgundy.controlColor
                )
                .accessibilityLabel(
                    crossAttempts == 0
                        ? "Try to push it across"
                        : "It will not go. Nothing crosses without both."
                )
        }
    }

    private var carriedLine: some View {
        Text(privateLine.isEmpty ? "Your private line" : privateLine)
            .font(.weBody)
            .foregroundStyle(.white.opacity(privateLine.isEmpty ? 0.4 : 0.92))
            .lineLimit(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: 210, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(WEHue.burgundy.color.opacity(0.55))
            )
    }

    private var crossGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Resistance rises with distance: the boundary pushes back
                // harder the more it is insisted on.
                let pushed = max(value.translation.width, 0)
                dragOffset = CGSize(width: min(pushed * 0.42, 54), height: 0)
            }
            .onEnded { _ in
                if dragOffset.width > 18 {
                    crossAttempts += 1
                    refusalTrigger += 1
                }
                withAnimation(settle(0.55)) { dragOffset = .zero }
            }
    }

    /// Consent needs two hands. The second control is real, present, and
    /// permanently out of reach in this screen. That is the point.
    private var bothHandsStage: some View {
        HStack(spacing: 12) {
            consentPad(
                title: "YOUR TAP",
                isFilled: yourTapLanded,
                isEnabled: true
            ) {
                yourTapLanded.toggle()
                hapticTrigger += 1
            }

            consentPad(
                title: "THEIRS",
                isFilled: false,
                isEnabled: false,
                caption: "Not yours to give"
            ) {}
        }
        .frame(maxWidth: .infinity)
    }

    private func consentPad(
        title: String,
        isFilled: Bool,
        isEnabled: Bool,
        caption: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(isEnabled ? 0.72 : 0.34))
                Circle()
                    .fill(isFilled ? WEHue.burgundy.controlColor : .clear)
                    .overlay(
                        Circle().strokeBorder(
                            .white.opacity(isEnabled ? 0.5 : 0.18),
                            lineWidth: 1
                        )
                    )
                    .frame(width: 42, height: 42)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(isEnabled ? 0.07 : 0.03))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(
            isEnabled
                ? "Your consent"
                : "Your partner's consent, which only they can give"
        )
    }

    /// Real product state, set before the account exists. Signals are the one
    /// place a person decides what the shared field is allowed to notice, so
    /// they get to decide it on the way in rather than find it in Settings.
    private var signalsStage: some View {
        VStack(spacing: 0) {
            ForEach(Array(SignalKind.allCases.enumerated()), id: \.element) { index, signal in
                Toggle(isOn: binding(for: signal)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(signal.title)
                            .font(.weBody)
                            .foregroundStyle(.white)
                        Text(signal.detail)
                            .font(.weCaption)
                            .fontWeight(.regular)
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(WEHue.burgundy.controlColor)
                .padding(.vertical, 12)

                if index < SignalKind.allCases.count - 1 {
                    Divider().overlay(.white.opacity(0.1))
                }
            }
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.05))
        )
    }

    private var thresholdStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.carried, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(WEHue.burgundy.controlColor)
                    Text(line)
                        .font(.weBody)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var action: some View {
        if beat == .threshold {
            Button {
                cross()
            } label: {
                Label(
                    hasCrossed ? "Crossed" : "Hold to cross",
                    systemImage: hasCrossed ? "checkmark" : "hand.tap"
                )
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.plain)
            .background(
                WEHue.burgundy.controlColor,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .foregroundStyle(.white)
            // Sighted users hold; under VoiceOver the single activation above
            // is the whole interaction, so the hold does nothing.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: reduceMotion ? 0.25 : 1.0)
                    .onEnded { _ in
                        guard !voiceOverEnabled else { return }
                        cross()
                    }
            )
            .accessibilityLabel("Cross into WE")
            .accessibilityHint("Press and hold to begin")
            .accessibilityIdentifier("thresholdCross")
            .padding(.top, 22)
        } else {
            Button {
                hapticTrigger += 1
                withAnimation(settle(0.5)) { beat = beat.next }
            } label: {
                Label(beat.advance, systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.plain)
            .background(
                WEHue.burgundy.controlColor,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .foregroundStyle(.white)
            .accessibilityIdentifier("thresholdContinue")
            .padding(.top, 22)
        }
    }

    private func cross() {
        guard !hasCrossed else { return }
        hasCrossed = true
        hapticTrigger += 1
        if reduceMotion || voiceOverEnabled {
            finish()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: finish)
        }
    }

    private func finish() {
        if mode == .firstRun {
            ThresholdIntent(
                privateLine: privateLine.trimmingCharacters(in: .whitespacesAndNewlines),
                signals: signals
            )
            .store()
        }
        onComplete()
    }

    // MARK: - Support

    private func binding(for signal: SignalKind) -> Binding<Bool> {
        Binding(
            get: { signals[signal.rawValue] ?? true },
            set: { signals[signal.rawValue] = $0 }
        )
    }

    private func settle(_ duration: Double) -> Animation? {
        .weSettle(duration: duration, reduceMotion: reduceMotion)
    }

    /// Their side stays dark. It brightens a little as the person commits, and
    /// never resolves — that resolution belongs to the partner's arrival.
    private var connection: CGFloat {
        switch beat {
        case .refusal: 0.05
        case .yourSide: 0.10
        case .boundary: 0.14
        case .bothHands: 0.22
        case .signals: 0.30
        case .threshold: hasCrossed ? 0.46 : 0.38
        }
    }

    private static let refusals = [
        "No score of you.",
        "No coach, no advice.",
        "No feed to keep up with.",
        "No way to read them behind their back."
    ]

    private static let carried = [
        "Your line is on this phone. It moves when you pair, and not before.",
        "Your signals are set. Change them any time in Profile.",
        "Next: your account, then the code that joins the two of you."
    ]
}

// MARK: - Beats

extension ThresholdWalkthrough {
    enum Beat: Int, CaseIterable {
        case refusal
        case yourSide
        case boundary
        case bothHands
        case signals
        case threshold

        var index: Int { rawValue }

        var next: Beat {
            Beat(rawValue: rawValue + 1) ?? .threshold
        }

        var label: String {
            switch self {
            case .refusal: "WHAT THIS IS NOT"
            case .yourSide: "YOUR SIDE"
            case .boundary: "THE BOUNDARY"
            case .bothHands: "BOTH HANDS"
            case .signals: "WHAT IT MAY NOTICE"
            case .threshold: "THE THRESHOLD"
            }
        }

        var title: String {
            switch self {
            case .refusal: "WE keeps out of your way."
            case .yourSide: "Write one private thing."
            case .boundary: "Now try to send it to them."
            case .bothHands: "One tap is never enough."
            case .signals: "You decide what it may notice."
            case .threshold: "You are ready to cross."
            }
        }

        var detail: String {
            switch self {
            case .refusal:
                "Two people, one private field. It holds what you carry and opens only when you both open it."
            case .yourSide:
                "Anything. It is yours, and it stays yours whatever happens next."
            case .boundary:
                "Go on. Push it toward their side of the field."
            case .bothHands:
                "Opening something takes your consent and theirs. The second pad is not yours to press, here or anywhere in WE."
            case .signals:
                "The shared field reads only what you both allow. Turn any of it off now, or later, without explaining yourself."
            case .threshold:
                "Everything from here belongs to the two of you."
            }
        }

        var advance: String {
            switch self {
            case .refusal: "Show me"
            case .yourSide: "Keep it"
            case .boundary: "I felt that"
            case .bothHands: "Understood"
            case .signals: "Save these"
            case .threshold: "Cross"
            }
        }
    }
}

// MARK: - Deferred intent

/// What the walkthrough collected before an account existed. It waits on the
/// device and is delivered once the two people are actually paired: the private
/// line becomes the first reflection, the signal choices become signal consent.
/// Nothing leaves the phone before that.
struct ThresholdIntent: Codable, Equatable {
    var privateLine: String
    var signals: [String: Bool]

    static let storageKey = "thresholdIntent"

    static let defaultSignals: [String: Bool] = [
        SignalKind.sharedPlans.rawValue: true,
        SignalKind.weeklyRhythm.rawValue: true,
        SignalKind.unfinishedThreads.rawValue: true,
        SignalKind.privateReflections.rawValue: false
    ]

    var isEmpty: Bool {
        privateLine.isEmpty && signals == Self.defaultSignals
    }

    func store(in defaults: UserDefaults = .standard) {
        guard !isEmpty else { return }
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func pending(in defaults: UserDefaults = .standard) -> ThresholdIntent? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ThresholdIntent.self, from: data)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    /// Called the first time the relationship is ready. Delivery is one-way and
    /// clears itself, so a line is never written twice.
    @MainActor
    static func deliverPending(
        to session: AppSession,
        defaults: UserDefaults = .standard
    ) async {
        guard let intent = pending(in: defaults) else { return }
        clear(in: defaults)

        for signal in SignalKind.allCases {
            guard let enabled = intent.signals[signal.rawValue],
                  enabled != (defaultSignals[signal.rawValue] ?? true)
            else { continue }
            await session.setSignalConsent(signal, enabled: enabled)
        }

        if !intent.privateLine.isEmpty {
            await session.saveReflection(text: intent.privateLine)
        }
    }
}

#Preview("First run") {
    ThresholdWalkthrough(onComplete: {})
}

#Preview("Replay") {
    ThresholdWalkthrough(mode: .replay, onComplete: {})
}
