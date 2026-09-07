import SwiftUI

/// A fictional practice session. No backend, session, outbox, or network resolver
/// is injected: every interaction is confined to this view's in-memory store.
@MainActor
struct WalkthroughView: View {
    let onFinish: () -> Void
    @State private var step = 0
    @State private var store = WalkthroughPractice.makeStore()
    @State private var openedItem: FieldItemReference?
    @State private var hasOpenedItem = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canvas: WECanvas { step == 3 ? .cream : .ground }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("An example. Nothing here is saved to your account.")
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.reasoning))
                    content
                }
                .padding(FieldMetrics.screenSide)
            }
            .safeAreaInset(edge: .bottom) {
                if step != 1 {
                    Button(actionLabel) { advance() }
                        .buttonStyle(FieldFilledButtonStyle())
                        .disabled(step == 3 && !hasOpenedItem)
                        .accessibilityIdentifier("walkthrough.next")
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(canvas.bg)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip", action: onFinish)
                        .accessibilityIdentifier("walkthrough.skip")
                }
            }
            .weCanvas(canvas)
            .environment(store)
            .preferredColorScheme(canvas == .cream ? .light : .dark)
            .sheet(item: $openedItem) { reference in
                FieldItemSheet(itemID: reference.id)
                    .environment(store)
            }
            .onChange(of: store.state.lifeItems.count) { _, count in
                if step == 1 && count > 0 { step = 2 }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            Text("A little less to carry.").font(FieldType.hero)
            Text("Put a thought down. See where it goes. Find it when you need it.")
                .font(FieldType.body)
            Text(WalkthroughPractice.input).font(FieldType.pageHeadline)
        case 1:
            Text("One thought, a place for it.").font(FieldType.pageHeadline)
            Text("Try this example. Review the date and who can see it before saving. Change Friday to Saturday if that works better.")
                .font(FieldType.body)
            FieldCaptureField()
        case 2:
            Text("Your thought has a place.").font(FieldType.pageHeadline)
            Text("Saved in this example. Now use Life to find the same item again.")
                .font(FieldType.body)
            if let item = store.state.lifeItems.first {
                Text(item.title).font(FieldType.pageHeadline)
                if let date = item.dueOn {
                    Text(date, format: .dateTime.weekday(.wide).month().day())
                        .font(FieldType.body)
                }
            }
        case 3:
            Text("Find it in Life.").font(FieldType.pageHeadline)
            Text("The same thought is here, with the date you chose. Open it to review or correct it.")
                .font(FieldType.body)
            ForEach(store.state.lifeItems) { item in
                Button {
                    hasOpenedItem = true
                    openedItem = FieldItemReference(id: item.id)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title).font(FieldType.pageHeadline)
                        Text("Life · " + item.category.word).font(FieldType.body)
                        if let date = item.dueOn {
                            Text(date, format: .dateTime.weekday(.wide).month().day())
                                .font(FieldType.body)
                        }
                        Text("Shared example").font(FieldType.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("walkthrough.savedItem")
            }
        default:
            Text("Space for you. Room for both.").font(FieldType.hero)
            Text("Yours is your private writing space. Life holds practical things you can find again. Check each item's visibility before saving or sharing.")
                .font(FieldType.body)
            Text("Us is where a shared question can become a direction you both choose. Joining WE does not give blanket permission to share your private writing.")
                .font(FieldType.body)
            Text("Next, you can try with something from your own life.")
                .font(FieldType.body)
        }
    }

    private var actionLabel: String {
        switch step {
        case 0: "Try the example"
        case 2: "Find it in Life"
        case 3: "What stays private?"
        default: "Continue to WE"
        }
    }

    private func advance() {
        if step == 0 {
            store.captureDraft = WalkthroughPractice.input
            step = 1
        } else if step == 2 || step == 3 {
            step += 1
        } else {
            onFinish()
        }
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
