import SwiftUI

/// The Joining: three beats, on two phones, and no way to finish alone.
///
/// This used to run after account creation and *before* pairing, which meant
/// the most important moment in the product was performed alone — a person
/// reading three sentences about mutual consent by themselves, then tapping
/// Continue. The rule each beat describes is supposed to be the rule
/// governing the beat, and it was not: one person could complete the whole
/// thing, and there was a Skip button, and a promise you can skip is a
/// licence agreement.
///
/// What is gone, and why:
///
///   · **Skip.** There is no dismiss affordance on any beat.
///   · **The step counter.** "01", "02". The ceremony reveals its own length
///     by ending. A counter is the app describing its own process.
///   · **The `architecture` diagram** — Mine, a vertical line, Theirs, with a
///     VoiceOver label reading "Consent threshold". If the mechanic needs a
///     picture, the mechanic is not being performed. The two devices are the
///     diagram; do not draw two rectangles with a line between them, and do
///     not draw a diagram of consent.
///   · **The eyebrows.** MINE, OFFERED, OURS.
///
/// HELD IS THE LOAD BEARING FRAME
///
/// One person has given the beat and the other has not. It must feel like
/// patience rather than like waiting for a server, and it must leak nothing
/// about the other person's timing: no spinner, no "waiting for Dylan", no
/// timestamp, no checkmark, no elapsed anything. `WECeremonyState` cannot
/// express "they acted and I have not", so this view cannot render it.
///
/// An hour into a held beat is identical to a second into one. That is the
/// position: any accumulating reassurance converts devotion into anxiety.
struct LivingConfluencePromise: View {
    let onComplete: () -> Void

    /// Reading rather than performing.
    ///
    /// CIRCLE.md §2 allows the word "Yours" to name the personal space twice
    /// in a lifetime, and this screen is replayable from Account — so without
    /// this, "twice" would mean "as often as somebody rereads the privacy
    /// promise". A replay is also not a ceremony: nothing is written, nothing
    /// waits on the other person, and the beats are simply shown.
    var isReplay = false

    /// Where the ceremony has got to. Owned by the caller so the same state
    /// can be driven by a live backend, a test, or a preview.
    @Binding var ceremony: WECeremonyState

    /// Called when this person gives the current beat.
    var keep: (WEBeat) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var landed = 0
    @State private var replayBeat = 0

    /// What the field is saying, which is only ever one of three things: the
    /// couple, this person having just given a beat, or a beat landing on both
    /// phones. `arrival` holds the last of those on screen long enough to be
    /// seen, because the beat resolves and moves on in the same instant.
    @State private var arrival: Task<Void, Never>?
    @State private var isArriving = false

    private var identity: FieldIdentity
    private var partnerName: String { identity.nameB }

    /// Which of the two hues is this person's own.
    ///
    /// Only ever used to strengthen *their own* colour when they act. Nothing
    /// on this screen may draw the partner acting, so nothing on this screen
    /// needs to know which of them the partner is.
    private var viewer: FieldOwner

    init(
        identity: FieldIdentity = .seed,
        viewer: FieldOwner = .a,
        isReplay: Bool = false,
        ceremony: Binding<WECeremonyState>,
        keep: @escaping (WEBeat) -> Void = { _ in },
        onComplete: @escaping () -> Void
    ) {
        self.identity = identity
        self.viewer = viewer
        self.isReplay = isReplay
        self._ceremony = ceremony
        self.keep = keep
        self.onComplete = onComplete
    }

    /// The resting reading of the field, from state this device can see.
    ///
    /// A held beat is *this* person having acted, and that is the only reason
    /// `oneActed` can ever be constructed here. A replay writes nothing and
    /// waits for nobody, so it never leaves `shared`.
    private var restingField: WEColourFieldState {
        guard !isReplay, let beat, ceremony.state(of: beat) == .held else {
            return .shared
        }
        return .oneActed(viewer)
    }

    private var beat: WEBeat? {
        isReplay
            ? (replayBeat < WEBeat.allCases.count
                ? WEBeat.allCases[replayBeat]
                : nil)
            : ceremony.currentBeat
    }

    private var state: WEBeatState {
        guard let beat else { return .kept }
        return isReplay ? .waiting : ceremony.state(of: beat)
    }

    var body: some View {
        ZStack {
            WECanvas.ground.bg.ignoresSafeArea()

            if let beat {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)

                    WEDisplayText(beat.title, role: .hero)
                        .padding(.bottom, 18)

                    Text(beat.detail(partner: partnerName))
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.sectionSubtitle))
                        .fieldLineHeight(1.6, size: 14.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    action(for: beat)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, FieldMetrics.usSide)
                .padding(.bottom, FieldMetrics.screenBottom(at: typeSize))
                .id(beat)
                // A crossfade, always. Sliding one beat away to reveal the
                // next makes the ceremony into a carousel somebody is
                // advancing rather than something resolving.
                .transition(.opacity)
            }

            // Both hues from the first beat. The field is the couple, not a
            // progress bar: it must not brighten as beats are kept, or it
            // becomes the step counter drawn in colour. The two moments it is
            // allowed to mark both settle back to exactly this, so beat three
            // is lit the same as beat one.
            WEColourField(
                state: isArriving ? .bothLanded : restingField,
                identity: identity,
                height: 168
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: beat)
        .environment(\.weCanvas, .ground)
        .preferredColorScheme(.dark)
        // One shared haptic, at the instant a beat is kept on both phones,
        // and nothing else in the whole ceremony. WE has no sound.
        .sensoryFeedback(.success, trigger: landed)
        .onChange(of: ceremony.kept) { old, new in
            guard new.count > old.count else { return }
            landed += 1
            markArrival()
        }
        .onChange(of: ceremony.isComplete) { _, complete in
            if complete, !isReplay { onComplete() }
        }
        // Deliberately no identifier on the root. An identifier on a
        // container is inherited by every descendant that would otherwise
        // carry its own, so naming the whole screen `we.promise` silently
        // renamed the give affordance and the held line to `we.promise` too —
        // leaving `we.promise.give` and `we.promise.held` matching nothing.
        // The beats are found by their own words, which is what a test should
        // be asserting about a promise anyway.
        .accessibilityElement(children: .contain)
        .onDisappear { arrival?.cancel() }
    }

    /// Holds `bothLanded` on the field for as long as the moment takes.
    ///
    /// The beat resolves to `kept` and `currentBeat` advances in the same
    /// instant, so a field derived purely from state would show the landing
    /// for a single frame. This is the one piece of ceremony timing that is
    /// not read from persisted state, and it is safe to hold locally precisely
    /// because it says nothing: it is triggered by the aggregate resolving,
    /// which both phones see at once, and it reports nobody's timing.
    private func markArrival() {
        arrival?.cancel()
        isArriving = true
        arrival = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            isArriving = false
        }
    }

    /// The way to give the beat, and what stands in its place once given.
    ///
    /// There is deliberately no third branch. `.kept` resolves into the next
    /// beat rather than rendering, and "they have given it and I have not" is
    /// not a state this device can be in.
    @ViewBuilder
    private func action(for beat: WEBeat) -> some View {
        switch state {
        case .waiting:
            WEEditorialAction(isReplay ? "Next" : "I understand") {
                if isReplay {
                    replayBeat += 1
                    if replayBeat >= WEBeat.allCases.count { onComplete() }
                } else {
                    keep(beat)
                }
            }
            .accessibilityIdentifier("we.promise.give")

        case .held:
            // Held. Not "waiting for Dylan", not a spinner, not a checkmark,
            // and nothing that changes as time passes. The sentence is about
            // what is true of the beat, never about the other person.
            Text("Held, until you have both said so.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.metadataProse))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("we.promise.held")

        case .kept:
            EmptyView()
        }
    }
}
