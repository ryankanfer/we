//
//  WalkthroughView.swift
//  WE
//
//  The first minute inside the app, played once, right after the account
//  exists.
//
//  Five beats, one idea each, drawn the way the rest of the app now is: on
//  the person's own ground (paper or dark), with two lights at the bottom,
//  one for each of them, that move with the story.
//
//    Hello            the two lights, apart
//    Three buttons    Today, +, Life. Tapping + opens the real card
//    Shared or yours  one switch, chosen before anything is saved; Only me
//                     turns their light off
//    Say it           a sentence types itself under the choice; the send
//                     button glows; the real classifier files it, and the
//                     card can be moved with the real list picker
//    Three promises   lit one at a time; "I'm in" merges the two lights
//
//  The Promise used to be a separate live ceremony on both phones. It lives
//  here now, as the last beat, where everybody meets it once.
//
//  Everything is held in this view. No store, no account, no outbox.
//

import SwiftUI

// MARK: - What the walkthrough knows about the person

/// Where the walkthrough hands off, decided by where the session actually is.
enum WalkthroughHandoff: Equatable {
    /// Account made, nobody paired yet. The pairing screen is underneath.
    case invite
    /// An invitation is out and the other person has not arrived.
    case waiting
    /// Already a couple, usually because they joined with a code.
    case open
    /// Asked for again from Account.
    case replay
}

struct WalkthroughSetting {
    var firstName: String?
    var partnerName: String?
    var identity: FieldIdentity = .seed
    var handoff: WalkthroughHandoff = .replay
    var isFirstRun = false

    static let preview = WalkthroughSetting(
        firstName: "Ry",
        partnerName: nil,
        handoff: .invite,
        isFirstRun: true
    )

    /// "your person" until there is somebody to name.
    var partnerWord: String {
        guard let name = partnerName?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else { return "your person" }
        return name
    }
}

// MARK: - The walkthrough

@MainActor
struct WalkthroughView: View {
    let setting: WalkthroughSetting
    let onFinish: () -> Void

    init(
        setting: WalkthroughSetting = .preview,
        onFinish: @escaping () -> Void
    ) {
        self.setting = setting
        self.onFinish = onFinish
    }

    private enum Step: Int, CaseIterable {
        // Who sees it comes before saying it, because that is the order the
        // app keeps: the choice is made before saving, and a shared thing is
        // never made private again. Teaching it the other way round showed a
        // saved card switching back to Only me, which nothing in WE can do.
        case hello, places, yours, say, promises
    }

    @State private var step: Step = .hello
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var headingFocused: Bool

    // Three buttons
    @State private var tab = 0
    @State private var tabIsCycling = true
    @State private var showsPlusCard = false

    // Say it
    @State private var draft = ""
    @State private var receipt: FieldReceipt?
    @State private var typingTask: Task<Void, Never>?
    @State private var pulse = 0
    @FocusState private var composing: Bool
    /// The real list picker, open under the filed card.
    @State private var isMoving = false

    // Shared or yours
    @State private var isPrivate = false

    // Promises
    @State private var lit = 1
    @State private var agreed = false

    private var canvas: WECanvas { WECanvas.surface }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.88)
    }

    private var identity: FieldIdentity {
        var identity = setting.identity
        identity.nameA = setting.firstName ?? "You"
        identity.nameB = setting.partnerName ?? "Your person"
        return identity
    }

    private var pose: WELightsPose {
        switch step {
        case .hello: .apart
        case .places: .near
        case .say: isPrivate ? .alone : (receipt == nil ? .near : .lifted)
        case .yours: isPrivate ? .alone : .near
        case .promises: agreed ? .merged : .near
        }
    }

    private var trimmedDraft: String {
        draft.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            canvas.bg.ignoresSafeArea()
            WELights(identity: setting.identity, pose: pose, pulse: pulse)

            VStack(spacing: 0) {
                topBar
                ZStack {
                    ForEach(Step.allCases, id: \.self) { candidate in
                        if candidate == step {
                            scene(candidate)
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .offset(y: 16))
                                )
                        }
                    }
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 26)
            }

            if showsPlusCard {
                WalkthroughPlusCard(
                    partner: setting.partnerWord,
                    identity: setting.identity,
                    onClose: { withAnimation(motion) { showsPlusCard = false } }
                )
                .transition(.opacity)
                .zIndex(5)
            }
        }
        .foregroundStyle(.fieldInk(.headline))
        .environment(\.weCanvas, canvas)
        .preferredColorScheme(WETheme.shared.colorScheme)
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.success, trigger: receipt?.id)
        .sensoryFeedback(.selection, trigger: isPrivate)
        .sensoryFeedback(.impact(weight: .light), trigger: lit)
        .onChange(of: step) { _, _ in headingFocused = true }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            if step == .hello {
                Text("WE")
                    .font(FieldType.mark)
                    .tracking(FieldTracking.mark * 1.4)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .accessibilityHidden(true)
            } else {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(.body, weight: .medium))
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("walkthrough.back")
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(canvas.ink.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    setting.identity.personA.color(on: canvas),
                                    setting.identity.personB.color(on: canvas),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 2)
            .animation(motion, value: step)
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            .accessibilityIdentifier("walkthrough.progress")

            Button(setting.isFirstRun ? "Skip" : "Close", action: onFinish)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.fieldInk(.reasoning))
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .accessibilityIdentifier("walkthrough.skip")
        }
        .padding(.horizontal, 26)
        .padding(.top, 6)
    }

    private var progress: CGFloat {
        agreed ? 1 : CGFloat(step.rawValue) / CGFloat(Step.allCases.count - 1)
    }

    // MARK: Scenes

    @ViewBuilder
    private func scene(_ step: Step) -> some View {
        switch step {
        case .hello: hello
        case .places: places
        case .say: say
        case .yours: yours
        case .promises: promises
        }
    }

    private func display(_ text: String, size: CGFloat = 52) -> some View {
        WEWordReveal(
            text: text,
            font: typeSize.isAccessibilitySize ? .system(.largeTitle, design: .serif) : FieldType.hero(size),
            tracking: -1,
            lineSpacing: 0
        )
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($headingFocused)
        .accessibilityIdentifier("walkthrough.heading")
    }

    private func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(FieldType.mark)
            .tracking(2.6)
            .foregroundStyle(.fieldInk(.label))
            .padding(.top, 26)
            .padding(.bottom, 12)
    }

    private func lede(_ text: String) -> some View {
        Text(text)
            .font(FieldType.hero(19))
            .foregroundStyle(.fieldInk(.reasoning))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
            .weArrival(delay: 0.35)
    }

    // MARK: Hello

    private var hello: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            display(helloTitle, size: 60)
            lede("This is where you and \(setting.partnerWord) keep the life you share.")
            Spacer().frame(height: 44)
            primary("Begin") { go(.places) }
        }
    }

    private var helloTitle: String {
        guard setting.isFirstRun else { return "How WE works." }
        if let name = setting.firstName, !name.isEmpty { return "Hi, \(name)." }
        return "Hi."
    }

    // MARK: Three buttons

    private let tabs: [(title: String, line: String)] = [
        ("Today", "What needs you today, one thing at a time."),
        ("Add anything", "A plan, a reminder, a link. In your own words."),
        ("Life", "Everything you\u{2019}ve saved, sorted for you."),
    ]

    private var places: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("The whole app")
            display("Three buttons. That\u{2019}s it.")
            Spacer(minLength: 20)

            VStack(spacing: 26) {
                VStack(spacing: 6) {
                    Text(tabs[tab].title)
                        .font(FieldType.hero(30))
                    Text(tabs[tab].line)
                        .font(.system(.subheadline))
                        .foregroundStyle(.fieldInk(.reasoning))
                }
                .multilineTextAlignment(.center)
                .id(tab)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .frame(minHeight: 74)

                HStack(spacing: 6) {
                    tabButton(0, "Today")
                    Button {
                        selectTab(1)
                        withAnimation(motion) { showsPlusCard = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(canvas.bg)
                            .frame(width: 52, height: 52)
                            .background(canvas.ink, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .weCoach(tab == 1 && !showsPlusCard, tint: setting.identity.personA.color(on: canvas))
                    .accessibilityLabel("Add something")
                    .accessibilityIdentifier("walkthrough.plus")
                    tabButton(2, "Life")
                }
                .padding(6)
                .weGlass(in: Capsule())

                Text("Tap + to see what it opens.")
                    .font(.system(.footnote))
                    .foregroundStyle(.fieldInk(.reasoning))
            }
            .frame(maxWidth: .infinity)
            .task(id: step) { await cycleTabs() }

            Spacer(minLength: 20)
            glassButton("Next") { go(.yours) }
        }
    }

    private func tabButton(_ index: Int, _ title: String) -> some View {
        Button { selectTab(index) } label: {
            Text(title)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.fieldInk(tab == index ? .headline : .reasoning))
                .frame(minWidth: 92, minHeight: 52)
                .background {
                    if tab == index {
                        Capsule().fill(canvas.ink.opacity(canvas.isDark ? 0.14 : 0.08))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == index ? .isSelected : [])
    }

    private func selectTab(_ index: Int) {
        tabIsCycling = false
        withAnimation(motion) { tab = index }
    }

    private func cycleTabs() async {
        guard step == .places, !reduceMotion else { return }
        tabIsCycling = true
        while !Task.isCancelled && tabIsCycling {
            try? await Task.sleep(for: .seconds(2.4))
            guard tabIsCycling, !Task.isCancelled else { return }
            withAnimation(motion) { tab = (tab + 1) % 3 }
        }
    }

    // MARK: Say it

    private var say: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("Try it")
            display("Say it like a text.")

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Keep something\u{2026}", text: $draft, axis: .vertical)
                    .font(FieldType.hero(21))
                    .lineLimit(1...4)
                    .focused($composing)
                    .tint(setting.identity.personA.color(on: canvas))
                    .onChange(of: draft) { _, _ in
                        if composing { typingTask?.cancel() }
                    }
                    .accessibilityIdentifier("walkthrough.composer")

                Button(action: file) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canvas.bg)
                        .frame(width: 42, height: 42)
                        .background(canvas.ink.opacity(trimmedDraft.isEmpty ? 0.25 : 1), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(trimmedDraft.isEmpty)
                .weCoach(sendIsWaiting, tint: setting.identity.personA.color(on: canvas))
                .accessibilityLabel("Send")
                .accessibilityIdentifier("walkthrough.send")
            }
            .padding(.leading, 22)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .weGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.top, 28)

            if receipt == nil {
                audienceLine
                    .padding(.top, 12)
                    .padding(.leading, 6)
            }

            if sendIsWaiting {
                HStack(spacing: 6) {
                    Text("Tap send")
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(setting.identity.personA.color(on: canvas))
                }
                .font(.system(.footnote, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 10)
                .padding(.trailing, 8)
                .transition(.opacity)
                .accessibilityHidden(true)
            }

            if receipt == nil {
                borrow.padding(.top, 16)
            } else if let receipt {
                filedCard(receipt)
                    .padding(.top, 22)
                    .transition(
                        reduceMotion ? .opacity
                            : .asymmetric(
                                insertion: .offset(y: -30).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                                removal: .opacity
                            )
                    )
            }

            Spacer(minLength: 16)
            glassButton("Next", enabled: receipt != nil) { go(.promises) }
                .accessibilityHint(receipt == nil ? "Send the sentence first" : "")
        }
        .task(id: step) {
            if receipt == nil, draft.isEmpty { typeOut(WalkthroughPractice.input) }
        }
    }

    /// The sentence is written and waiting: the one moment the screen is
    /// asking for a single tap, and it says so.
    private var sendIsWaiting: Bool {
        receipt == nil && !trimmedDraft.isEmpty && typingTask == nil
    }

    private var borrow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WalkthroughPractice.suggestions.filter { $0 != trimmedDraft }, id: \.self) { line in
                    Button { typeOut(line) } label: {
                        Text(line)
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(.fieldInk(.reasoning))
                            .padding(.horizontal, 13)
                            .frame(minHeight: 36)
                            .overlay(Capsule().strokeBorder(canvas.ink.opacity(0.14), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    /// Types a sentence into the field a letter at a time, the way a person
    /// would, then stops and lets the send button ask for the tap.
    private func typeOut(_ sentence: String) {
        typingTask?.cancel()
        composing = false
        draft = ""
        guard !reduceMotion else { draft = sentence; typingTask = nil; return }
        typingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            for character in sentence {
                if Task.isCancelled { return }
                draft.append(character)
                try? await Task.sleep(for: .milliseconds(42))
            }
            typingTask = nil
        }
    }

    /// The real classifier, asked about the real week.
    private func file() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        typingTask?.cancel()
        typingTask = nil
        composing = false
        let filed = FieldClassifier.classify(
            text,
            context: FieldClassifier.Context(
                identity: identity,
                speaker: .a,
                now: WalkthroughSeed.anchor(Date()),
                lifeItems: [],
                horizons: [],
                rhythms: [],
                corrections: []
            )
        )
        var saved = filed
        saved.isPrivate = isPrivate
        withAnimation(motion) {
            receipt = saved
            draft = ""
            isMoving = false
        }
        pulse += 1
    }

    /// The same context `file()` used, so a move recovers the same date.
    private var practiceContext: FieldClassifier.Context {
        FieldClassifier.Context(
            identity: identity,
            speaker: .a,
            now: WalkthroughSeed.anchor(Date()),
            lifeItems: [],
            horizons: [],
            rhythms: [],
            corrections: []
        )
    }

    /// Who will see it, said under the sentence before it is sent. One tap
    /// changes it, here, before saving: the only moment it can go both ways.
    private var audienceLine: some View {
        Button {
            withAnimation(motion) { isPrivate.toggle() }
        } label: {
            HStack(spacing: 8) {
                audienceMark
                Text(isPrivate ? "Only me" : "You and \(setting.partnerWord)")
                    .font(.system(.footnote, weight: .medium))
                    .contentTransition(.opacity)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.fieldInk(.label))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .overlay(Capsule().strokeBorder(canvas.ink.opacity(isPrivate ? 0.35 : 0.14), style: StrokeStyle(lineWidth: 1, dash: isPrivate ? [4, 3] : [])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Who sees it")
        .accessibilityValue(isPrivate ? "Only me" : "You and \(setting.partnerWord)")
        .accessibilityHint("Changes who will see it, before you send")
        .accessibilityIdentifier("walkthrough.audience")
    }

    /// Two lights, or one: the same mark the switch draws.
    private var audienceMark: some View {
        ZStack(alignment: .leading) {
            Circle().fill(setting.identity.personB.color(on: canvas))
                .frame(width: 8, height: 8)
                .offset(x: 7)
                .opacity(isPrivate ? 0 : 1)
            Circle().fill(setting.identity.personA.color(on: canvas))
                .frame(width: 8, height: 8)
        }
        .frame(width: 16, alignment: .leading)
    }

    private func filedCard(_ receipt: FieldReceipt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // The card is the real control: tapping it opens the same list
            // picker the app uses, and a move refiles it the way the app does.
            Button {
                withAnimation(motion) { isMoving.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(receipt.category.label)
                        Spacer()
                        Text(receipt.isPrivate ? "ONLY ME" : "SHARED")
                    }
                    .font(FieldType.subLabel)
                    .tracking(2.2)
                    .foregroundStyle(.fieldInk(.label))
                    .contentTransition(.opacity)

                    Text(receipt.title)
                        .font(FieldType.hero(30))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if receipt.category.carriesDates, let due = receipt.dueOn {
                        Text(
                            receipt.endsOn.map { FieldPhrasing.spanLabel(due, $0) }
                                ?? due.formatted(.dateTime.weekday(.wide).month(.wide).day())
                        )
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .contentTransition(.opacity)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Moves it to another list")
            .accessibilityIdentifier("walkthrough.savedItem")

            Rectangle().fill(canvas.ink.opacity(0.08)).frame(height: 1).padding(.top, 4)

            if isMoving {
                FieldCategoryPicker(
                    options: LifeCategory.builtIn + [.notes],
                    choose: { move(to: $0) },
                    name: { name in
                        guard let category = LifeCategory(named: name) else { return nil }
                        move(to: category)
                        return category
                    },
                    cancel: { withAnimation(motion) { isMoving = false } },
                    selected: receipt.category,
                    selectedTint: setting.identity.personA.color(on: canvas)
                )
                .transition(.opacity)
            } else {
                Text(receipt.wasCorrected ? "Moved. WE learns from that." : "Wrong spot? Tap it and move it.")
                    .font(FieldType.reasoning)
                    .italic()
                    .foregroundStyle(.fieldInk(.reasoning))
                    .contentTransition(.opacity)
            }

            // The rule, said once, at the moment it starts to apply.
            Text(
                receipt.isPrivate
                    ? "Only you, for now. Share it when it\u{2019}s ready."
                    : "Shared stays shared. Choose Only me before you send."
            )
            .font(.system(.footnote))
            .foregroundStyle(.fieldInk(.label))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .weGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    canvas.ink.opacity(receipt.isPrivate ? 0.3 : 0),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
    }

    /// A move, made the way the app makes one. Nothing is recorded: the
    /// walkthrough touches no account.
    private func move(to category: LifeCategory) {
        guard var current = receipt else { return }
        let keepsPrivate = current.isPrivate
        current = FieldClassifier.correct(current, to: category, context: practiceContext).receipt
        current.isPrivate = keepsPrivate
        withAnimation(motion) {
            receipt = current
            isMoving = false
        }
    }

    // MARK: Shared or yours

    private var yours: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("Who sees it")
            display("Shared, or just yours.")

            // Chosen first, before there is anything to save. That is the
            // order the app keeps, so it is the order taught.
            HStack(spacing: 10) {
                audienceMark
                Text(isPrivate ? "Only you, for now" : "You and \(setting.partnerWord)")
                    .font(FieldType.body)
                    .contentTransition(.opacity)
                Spacer()
                Image(systemName: isPrivate ? "lock.fill" : "person.2")
                    .imageScale(.small)
                    .foregroundStyle(.fieldInk(.label))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.top, 26)
            .accessibilityElement(children: .combine)

            visibilitySwitch.padding(.top, 16)

            Text(
                isPrivate
                    ? "For a gift idea or a surprise. Share it when it\u{2019}s ready, or pick a day and you\u{2019}ll be asked then."
                    : "\(setting.partnerName ?? "They") see\(setting.partnerName == nil ? "" : "s") it too, in their Today and Life."
            )
            .font(FieldType.hero(18))
            .foregroundStyle(.fieldInk(.reasoning))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .padding(.top, 16)

            // The one way rule, plainly. Private can become shared; shared
            // never goes back.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.right")
                    .imageScale(.small)
                Text("You choose before you send. Only me can be shared later. Shared stays shared.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(.footnote, weight: .medium))
            .foregroundStyle(.fieldInk(.label))
            .padding(.top, 18)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 16)
            glassButton("Next") { go(.say) }
        }
    }

    private var visibilitySwitch: some View {
        HStack(spacing: 0) {
            segment("Both of us", selected: !isPrivate, identifier: "walkthrough.visibility.shared") {
                isPrivate = false
            }
            segment("Only me", selected: isPrivate, identifier: "walkthrough.visibility.private") {
                isPrivate = true
            }
        }
        .padding(5)
        .background(alignment: isPrivate ? .trailing : .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(canvas.ink)
                    .frame(width: proxy.size.width / 2 - 5)
                    .offset(x: isPrivate ? proxy.size.width / 2 : 5)
                    .padding(.vertical, 5)
            }
        }
        .weGlass(in: Capsule())
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75), value: isPrivate)
    }

    private func segment(_ title: String, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(selected ? AnyShapeStyle(canvas.bg) : AnyShapeStyle(.fieldInk(.reasoning)))
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    // MARK: Promises

    private let promiseLines: [(title: String, line: String)] = [
        ("Yours stays yours.", "Anything you mark Only me, only you see. Share it when you\u{2019}re ready; shared stays shared."),
        ("Nothing moves without you.", "Nothing private is shared unless you say yes."),
        ("Big things, decided together.", "You both answer. Neither of you sees the other first."),
    ]

    private var promises: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                kicker("Three promises")
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(promiseLines.enumerated()), id: \.offset) { index, promise in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(promise.title)
                                .font(FieldType.hero(30))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(promise.line)
                                .font(FieldType.body)
                                .foregroundStyle(.fieldInk(.reasoning))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .opacity(index < lit ? 1 : 0.16)
                        .offset(x: index < lit || reduceMotion ? 0 : -6)
                        .animation(motion, value: lit)
                        .accessibilityHidden(index >= lit)
                    }
                }
                .padding(.top, 8)

                Spacer(minLength: 16)
                primary(lit < promiseLines.count ? "Next promise" : "I\u{2019}m in") {
                    if lit < promiseLines.count {
                        lit += 1
                    } else {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.2)) { agreed = true }
                        pulse += 1
                    }
                }
            }
            .opacity(agreed ? 0 : 1)
            .allowsHitTesting(!agreed)
            .accessibilityHidden(agreed)

            if agreed {
                VStack(spacing: 14) {
                    Spacer()
                    WEWordReveal(
                        text: finaleTitle,
                        font: FieldType.hero(52),
                        tracking: -1,
                        alignment: .center
                    )
                    Text("Everything you just saw works best with two.")
                        .font(FieldType.hero(18))
                        .foregroundStyle(.fieldInk(.reasoning))
                        .multilineTextAlignment(.center)
                        .weArrival(delay: 0.8)
                    Spacer()
                    primary(handoffTitle, action: onFinish)
                        .weArrival(delay: 1.1)
                }
                .transition(.opacity)
            }
        }
    }

    private var finaleTitle: String {
        switch setting.handoff {
        case .invite: "Now, bring in your person."
        case .waiting: "Your invitation is ready."
        case .open: "You\u{2019}re in, together."
        case .replay: "That\u{2019}s WE."
        }
    }

    private var handoffTitle: String {
        switch setting.handoff {
        case .invite: "Bring in \(setting.partnerWord)"
        case .waiting: "Back to your invitation"
        case .open: "Open WE"
        case .replay: "Done"
        }
    }

    // MARK: Buttons

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                Image(systemName: "arrow.right").imageScale(.small)
            }
        }
        .buttonStyle(FirstRunPrimaryButtonStyle())
        .accessibilityIdentifier("walkthrough.next")
    }

    private func glassButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                Image(systemName: "arrow.right").imageScale(.small)
            }
        }
        .buttonStyle(FirstRunSecondaryButtonStyle())
        .disabled(!enabled)
        .accessibilityIdentifier("walkthrough.next")
    }

    // MARK: Moving

    private func go(_ next: Step) {
        typingTask?.cancel()
        typingTask = nil
        composing = false
        withAnimation(motion) { step = next }
    }

    private func back() {
        if agreed { withAnimation(motion) { agreed = false }; return }
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        go(previous)
    }
}

// MARK: - The + card, as it really looks

/// What + opens in the app, drawn over the walkthrough. A sentence types
/// itself, says where it will go, and the send button asks for the tap.
private struct WalkthroughPlusCard: View {
    let partner: String
    let identity: FieldIdentity
    let onClose: () -> Void

    @Environment(\.weCanvas) private var canvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var onlyMe = false
    @State private var saved = false
    @State private var shown = false

    private let sentence = "Book a table for Saturday"

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if saved {
                        Text("Saved to Food.")
                            .foregroundStyle(.fieldInk(.reasoning))
                    } else if text.isEmpty {
                        Text("Keep something\u{2026}")
                            .foregroundStyle(.fieldInk(.label))
                    } else {
                        Text(text)
                    }
                }
                .font(.system(size: 19, design: .serif))
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)

                Text(text.count == sentence.count && !saved ? "Goes to Food" : " ")
                    .font(.system(size: 12))
                    .foregroundStyle(.fieldInk(.legend))

                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 14))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(canvas.ink.opacity(0.15), lineWidth: 1))
                        .accessibilityHidden(true)

                    Button { onlyMe.toggle() } label: {
                        HStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .strokeBorder(identity.personA.color(on: canvas), lineWidth: 1.4)
                                    .frame(width: 16, height: 16)
                                    .offset(x: onlyMe ? 0 : -5)
                                if !onlyMe {
                                    Circle()
                                        .strokeBorder(identity.personB.color(on: canvas), lineWidth: 1.4)
                                        .frame(width: 16, height: 16)
                                        .offset(x: 5)
                                }
                            }
                            .frame(width: 28, height: 18)
                            Text(onlyMe ? "Only me" : "Both of us")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 11)
                        .frame(minHeight: 36)
                        .overlay(Capsule().strokeBorder(canvas.ink.opacity(0.2), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { saved = true }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(900))
                            onClose()
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(canvas.bg)
                            .frame(width: 44, height: 44)
                            .background(canvas.ink.opacity(canSend ? 1 : 0.2), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .weCoach(canSend, tint: identity.personA.color(on: canvas))
                    .accessibilityLabel("Send")
                }

                Text(onlyMe ? WEOnlyMeCopy.on(partner: partner) : "\(partner.prefix(1).uppercased() + partner.dropFirst()) will see this.")
                    .font(.system(size: 12))
                    .foregroundStyle(.fieldInk(.legend))
            }
            .padding(20)
            .weGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(canvas.ink.opacity(onlyMe ? 0.35 : 0), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .padding(.horizontal, 16)
            .scaleEffect(shown || reduceMotion ? 1 : 0.9)
            .opacity(shown ? 1 : 0)
        }
        .task {
            withAnimation(.spring(duration: 0.42, bounce: 0.22)) { shown = true }
            try? await Task.sleep(for: .milliseconds(450))
            for character in sentence {
                if Task.isCancelled { return }
                text.append(character)
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 45))
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var canSend: Bool { text.count == sentence.count && !saved }
}

// MARK: - Practice material

@MainActor
enum WalkthroughPractice {
    static let input = "That little Italian place for Friday."

    /// Ordinary sentences, the kind people actually type. Whatever the
    /// classifier makes of them is what the walkthrough shows.
    static let suggestions: [String] = [
        input,
        "Pay the electric bill by the 15th",
        "Book a weekend upstate this fall",
        "Call the vet about Miso on Tuesday",
    ]

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
/// week on every step change merely to redraw a caption.
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
    private var silence: some View {
        WalkthroughScaffold(
            journey: journey,
            onClose: onClose
        ) {
            EmptyView()
        } caption: {
            WalkthroughBeat(
                label: "Nothing to show",
                line: "Nothing to show rather than an invented example."
            )
        }
    }
}

#Preview("Walkthrough, first run") {
    WalkthroughView(onFinish: {})
}

#Preview("Walkthrough, replay") {
    WalkthroughView(
        setting: WalkthroughSetting(
            firstName: "Ry",
            partnerName: "Dylan",
            handoff: .replay
        ),
        onFinish: {}
    )
}
