import SwiftUI

/// One small, real interaction, held entirely in memory. This view never receives
/// an account, backend, or outbox; replay starts with a fresh practice store.
@MainActor
struct WalkthroughView: View {
    let onFinish: () -> Void
    @State private var step = 0
    @State private var store = WalkthroughPractice.makeStore()
    @State private var openedItem: FieldItemReference?
    @State private var selectedSpace = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var headingFocused: Bool

    private var canvas: WECanvas { step == 0 || step == 4 ? .ground : .cream }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.45) }
    private var titles: [String] {
        ["Make room for\nthe good part.", "Start with\na thought.",
         "You decide what\ngets saved.", "Now it has\na place.",
         "Life together.\nSpace for yourself."]
    }
    private var details: [String] {
        ["A dinner you keep meaning to plan. A detail you don’t want to forget. A little less to carry between you.",
         "An ordinary sentence is enough. Try this one, or make it your own.",
         "Check the date and the version you’re sharing. This practice plan is a shared example; nothing here is sent to anyone.",
         "Your dinner idea is in Life, with the date you chose. Open it to check or change the details.",
         "A place for the practical things, the personal things, and what you choose together."]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            Color.clear.frame(height: 0).id("top")
                            if step == 0 && !typeSize.isAccessibilitySize {
                                WalkthroughDinnerScene(appeared: appeared)
                                    .frame(height: 230)
                                    .dynamicTypeSize(.large)
                                    .accessibilityHidden(true)
                            }
                            introduction
                            stage
                        }
                        .frame(maxWidth: 480, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 30)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: step) { _, _ in
                        proxy.scrollTo("top", anchor: .top)
                        headingFocused = true
                    }
                }
                footer
            }
            .background(canvas.bg.ignoresSafeArea())
            .weCanvas(canvas)
            .environment(store)
            .environment(\.colorScheme, canvas == .cream ? .light : .dark)
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $openedItem) { reference in
                FieldItemSheet(itemID: reference.id)
                    .environment(store)
                    .weCanvas(.cream)
                    .environment(\.colorScheme, .light)
            }
            .onChange(of: store.lastReceipt != nil) { _, reviewing in
                if reviewing && step == 1 { move(to: 2) }
                else if !reviewing && step == 2 { move(to: 1) }
            }
            .onAppear { withAnimation(motion) { appeared = true } }
            .animation(motion, value: canvas)
            .sensoryFeedback(.selection, trigger: step)
        }
    }

    private var header: some View {
        HStack {
            Text("WE").font(FieldType.mark).tracking(4)
            if !typeSize.isAccessibilitySize {
                Rectangle().fill(WECanvas.ground.ink.opacity(0.2)).frame(width: 1, height: 18)
                    .padding(.horizontal, 8)
                Text("ONE LITTLE PLAN").font(FieldType.subLabel).tracking(2)
            }
            Spacer()
            Button(action: onFinish) {
                Text("Skip")
                    .font(FieldType.button)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("walkthrough.skip")
        }
        .foregroundStyle(.fieldInk(.headline))
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .weCanvas(.ground, ignoringSafeArea: false)
        .background(WECanvas.ground.bg.ignoresSafeArea(edges: .top))
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(typeSize.isAccessibilitySize ? titles[step].replacingOccurrences(of: "\n", with: " ") : titles[step])
                .font(typeSize.isAccessibilitySize ? .system(.title, design: .serif) : FieldType.hero)
                .padding(.vertical, 4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .accessibilityIdentifier("walkthrough.heading")
            Text(details[step])
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.fieldInk(.headline))
        .id(step)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
    }

    @ViewBuilder private var stage: some View {
        if step == 1 || step == 2 {
            // Keep the same component alive across composition and review so
            // keyboard focus, correction, and the receipt are not recreated.
            VStack(alignment: .leading, spacing: 18) {
                Label("Practice only · nothing saved to your account", systemImage: "lock")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.reasoning))
                FieldCaptureField(isWalkthrough: true, onSaved: { _ in move(to: 3) })
            }
        } else if step == 3 {
            savedPlan
        } else if step == 4 {
            spaces
        }
    }

    private var savedPlan: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("Saved in this example").font(FieldType.body)
            }
            .foregroundStyle(.fieldInk(.headline))
            ForEach(store.state.lifeItems) { item in
                Button {
                    openedItem = FieldItemReference(id: item.id)
                } label: {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            Text("LIFE / " + item.category.word.uppercased())
                                .font(FieldType.subLabel).tracking(2)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        Text(item.title).font(FieldType.pageHeadline)
                            .multilineTextAlignment(.leading)
                        if let date = item.dueOn {
                            Label {
                                Text(date, format: .dateTime.weekday(.wide).month().day())
                            } icon: { Image(systemName: "calendar") }
                            .font(FieldType.body)
                        }
                        Divider()
                        HStack {
                            Text("Shared example")
                            Spacer()
                            Text("Open plan")
                            Image(systemName: "arrow.right")
                        }
                        .font(FieldType.button)
                    }
                    .padding(24)
                    .foregroundStyle(.fieldInk(.headline))
                    .background(canvas.bgElevated, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(canvas.ink.opacity(0.12)))
                }
                .buttonStyle(WalkthroughPressStyle())
                .accessibilityIdentifier("walkthrough.savedItem")
            }
            Text("Find it again in Life. Search for a detail, or use Calendar for dated plans.")
                .font(FieldType.body).foregroundStyle(.fieldInk(.reasoning))
        }
        .transition(.opacity)
    }

    private var spaces: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                ForEach(0..<2) { index in
                    Button { withAnimation(motion) { selectedSpace = index } } label: {
                        VStack(spacing: 12) {
                            Text(["Today", "Life"][index])
                                .font(FieldType.button)
                            Capsule()
                                .fill(selectedSpace == index ? canvas.ink : canvas.ink.opacity(0.12))
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSpace == index ? .isSelected : [])
                    .accessibilityIdentifier("walkthrough.space.\(index)")
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                Text(["A place to begin, every day.", "Where everything lives."][selectedSpace])
                    .font(FieldType.pageHeadline)
                Text([
                    "The day's conversation: one thing worth doing now, what you both added, and where WE filed it. Tap + to add anything, or paste a link.",
                    "Search sits in the middle when you need something fast. Below it: where you're headed, then every group — Care, Food, Trips and the rest."
                ][selectedSpace])
                .font(FieldType.body).foregroundStyle(.fieldInk(.sectionSubtitle))
                .lineSpacing(4)
                if selectedSpace == 0 {
                    Divider().overlay(canvas.ink.opacity(0.15))
                    Label("Only me · anything you add can be kept just for you", systemImage: "lock")
                        .font(FieldType.body)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .id(selectedSpace)
            .transition(.opacity)
            Text("Decide on this together turns anything shared into a choice you both agree to.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.reasoning))
            if WEFeatureFlags.shareInboxEnabled {
                DisclosureGroup("Save something from elsewhere") {
                    Text("Bring in a thought, link, or image from Life or the Share Sheet. Only Me means private wherever it appears. Review a separate version before sharing; your original stays private.")
                    Text("You choose when WE may open a website. Edit suggested details and dates, or ask Why this? to see the evidence. Needs attention in Account keeps unresolved work reachable.")
                }
                .font(FieldType.body)
                .accessibilityIdentifier("walkthrough.imports")
            }
            Text("Joining WE never gives blanket permission to share your private writing.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.reasoning))
        }
        .foregroundStyle(.fieldInk(.headline))
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<5) { index in
                    Capsule().fill(canvas.ink.opacity(index <= step ? 0.8 : 0.16))
                        .frame(height: 2)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of 5")
            .accessibilityIdentifier("walkthrough.progress")
            HStack(spacing: 18) {
                if step > 0 {
                    Button(action: goBack) {
                        Image(systemName: "arrow.left").frame(width: 48, height: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("walkthrough.back")
                }
                if step == 0 || step >= 3 {
                    Button {
                        if step == 4 { onFinish() }
                        else if step == 0 {
                            store.captureDraft = WalkthroughPractice.input
                            move(to: 1)
                        } else { move(to: 4) }
                    } label: {
                        HStack {
                            Text(step == 0 ? "Try a little example" : step == 3 ? "Meet the rest of WE" : "Get started")
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.right")
                        }
                        .font(FieldType.button)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 56)
                        .foregroundStyle(canvas.bg)
                        .background(canvas.ink, in: Capsule())
                    }
                    .buttonStyle(WalkthroughPressStyle())
                    .accessibilityIdentifier("walkthrough.next")
                } else {
                    Text(step == 1 ? "Start with the example above." : "Review and save the example above.")
                        .font(FieldType.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.fieldInk(.headline))
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(canvas.bg)
    }

    private func move(to next: Int) {
        withAnimation(motion) { step = next }
    }

    private func goBack() {
        if step == 2 {
            let input = store.lastReceipt?.input ?? store.captureDraft
            store.lastReceipt = nil
            store.correctingReceipt = nil
            store.captureDraft = input
            move(to: 1)
        } else if step == 3 {
            store = WalkthroughPractice.makeStore()
            store.captureDraft = WalkthroughPractice.input
            move(to: 1)
        } else { move(to: max(0, step - 1)) }
    }
}

/// A little table for two, drawn in the app's two person pigments. Motion
/// brings the place settings together once; nothing loops or demands attention.
private struct WalkthroughDinnerScene: View {
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                Ellipse()
                    .fill(Color(hex: 0x24241D))
                    .overlay(Ellipse().strokeBorder(Color(hex: 0x85785F).opacity(0.35)))
                    .frame(width: width * 0.92, height: 206)
                    .rotationEffect(.degrees(-12))
                placeSetting(color: Color(hex: 0x9A6269))
                    .offset(x: -width * 0.24, y: appeared ? -26 : -46)
                placeSetting(color: Color(hex: 0x9AAB8B))
                    .offset(x: width * 0.24, y: appeared ? 26 : 46)
                VStack(spacing: 10) {
                    Text("a little plan").font(FieldType.body).italic()
                    Rectangle().fill(WECanvas.cream.ink.opacity(0.2)).frame(width: 28, height: 1)
                    Text("just us two").font(FieldType.subLabel).tracking(1.5)
                }
                .foregroundStyle(WECanvas.cream.ink)
                .padding(.horizontal, 20).padding(.vertical, 25)
                .background(WECanvas.cream.bg, in: RoundedRectangle(cornerRadius: 2))
                .rotationEffect(.degrees(appeared ? -8 : -16))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 12)
            }
            .frame(width: width, height: geometry.size.height)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
        }
    }

    private func placeSetting(color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.18))
            Circle().strokeBorder(color.opacity(0.8), lineWidth: 1)
            Circle().strokeBorder(color.opacity(0.4), lineWidth: 1).padding(10)
            Circle().strokeBorder(color.opacity(0.25), lineWidth: 0.5).padding(16)
        }
        .frame(width: 100, height: 100)
    }
}

private struct WalkthroughPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

@MainActor
enum WalkthroughPractice {
    static let input = "That little Italian place for Friday."
    // Monday, September 7, 2026. Fixed noon avoids midnight/DST ambiguity.
    static let date = Calendar.gregorianUS.date(from: DateComponents(
        year: 2026, month: 9, day: 7, hour: 12
    ))!

    static func makeStore() -> FieldStore {
        FieldStore(
            state: .empty(nameA: "You", nameB: "Your partner", now: date),
            now: date
        )
    }
}

// MARK: - Hosting one journey

/// Resolves the real example for one space and offers the next space.
///
/// The engine is asked once, in `init`, and the answer is held. Not a computed
/// property: `FieldClassifier.classify` and the two proposal functions are
/// pure but not free, and a computed one would re-derive the couple's whole
/// week on every step change merely to redraw a caption. `WalkthroughView`
/// gives this an `.id` per journey, so "once" means once per journey.
struct WalkthroughJourneyView: View {
    let journey: WalkthroughJourney
    let now: Date
    let onNextJourney: (WalkthroughJourney) -> Void
    let onClose: () -> Void

    private let outcome: WalkthroughOutcome?

    init(
        journey: WalkthroughJourney,
        now: Date,
        onNextJourney: @escaping (WalkthroughJourney) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.journey = journey
        self.now = now
        self.onNextJourney = onNextJourney
        self.onClose = onClose
        self.outcome = WalkthroughOutcome.resolve(journey, now: now)
    }

    var body: some View {
        switch outcome {
        case .movement(let receipt):
            WalkthroughMovement(
                receipt: receipt,
                journey: journey,
                onNextJourney: onNextJourney,
                onClose: onClose
            )
        case .context(let proposal):
            WalkthroughContext(
                proposal: proposal,
                journey: journey,
                onNextJourney: onNextJourney,
                onClose: onClose
            )
        case .memory(let proposal):
            WalkthroughMemory(
                proposal: proposal,
                now: now,
                journey: journey,
                onClose: onClose
            )
        case nil:
            silence
        }
    }

    /// The rule declined to fire, so there is nothing true to show.
    ///
    /// This is not a designed state and should be unreachable —
    /// `WalkthroughTests` asserts every journey resolves. It exists because
    /// the alternative to handling `nil` is forcing it, and an explanation
    /// that crashes rather than admit it has nothing to say is the worst of
    /// the available behaviours.
    private var silence: some View {
        WalkthroughScaffold(
            journey: journey,
            onClose: onClose
        ) {
            EmptyView()
        } caption: {
            WalkthroughBeat(
                label: "Nothing to show",
                line: "WE would rather say nothing than invent an example."
            )
        }
    }
}

#Preview("Walkthrough") {
    WalkthroughView(onFinish: {})
}
