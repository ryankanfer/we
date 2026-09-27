//
//  WalkthroughView.swift
//  WE
//
//  The first minute inside the app, played once, right after the account
//  exists.
//
//  It lives on the same paper as sign up and pairing, because it sits between
//  them. The app itself only appears as dark tiles on that paper: a window
//  into the product rather than a second canvas switching on and off. The
//  old version flipped between black and cream on every step, which read as
//  two apps arguing.
//
//  Four moves, each one a thing the person does rather than reads:
//
//    01 Say it        type a thought, any thought
//    02 It lands      the real classifier files it, and it can be moved
//    03 Yours or ours the same card, shared or Only me
//    04 Two places    Today and Life, with their thought already in both
//
//  Everything is held in this view's state. No store, no account, no outbox:
//  the receipt comes back from `FieldClassifier.classify` at the moment it is
//  asked for, so the example cannot drift from what the app actually does.
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
        case hello, say, lands, yours, map

        /// The four chapters. Hello is the cover, not a chapter.
        static let chapters: [Step] = [.say, .lands, .yours, .map]
    }

    @State private var step: Step = .hello
    @State private var forward = true
    @State private var draft = WalkthroughPractice.input
    @State private var original: FieldReceipt?
    @State private var receipt: FieldReceipt?
    @State private var isPrivate = false
    @State private var arrived = false
    @FocusState private var composing: Bool
    @AccessibilityFocusState private var headingFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88)
    }

    private var identity: FieldIdentity {
        var identity = setting.identity
        identity.nameA = setting.firstName ?? "You"
        identity.nameB = setting.partnerName ?? "Your person"
        return identity
    }

    private var trimmedDraft: String {
        draft
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        page
                            .id(step)
                            .transition(pageTransition)
                    }
                    .frame(maxWidth: FirstRunMetrics.column, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, FirstRunMetrics.side)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: step) { _, _ in
                    proxy.scrollTo("top", anchor: .top)
                    headingFocused = true
                }
            }
            actions
        }
        .background(WECanvas.cream.bg.ignoresSafeArea())
        .foregroundStyle(.fieldInk(.headline))
        .environment(\.weCanvas, .cream)
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.2)) {
                arrived = true
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.success, trigger: receipt?.id)
        .sensoryFeedback(.selection, trigger: isPrivate)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? 28 : -28)),
            removal: .opacity
        )
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 14) {
            if step == .hello {
                Text("WE")
                    .font(FieldType.mark)
                    .tracking(FieldTracking.mark)
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

            progress
                .opacity(step == .hello ? 0 : 1)

            Button(setting.isFirstRun ? "Skip" : "Close", action: onFinish)
                .buttonStyle(FirstRunLinkStyle())
                .frame(minWidth: 44, alignment: .trailing)
                .accessibilityIdentifier("walkthrough.skip")
        }
        .padding(.horizontal, FirstRunMetrics.side)
        .padding(.top, 4)
        .frame(maxWidth: FirstRunMetrics.column + FirstRunMetrics.side * 2)
        .frame(maxWidth: .infinity)
    }

    private var progress: some View {
        let index = Step.chapters.firstIndex(of: step) ?? -1
        return HStack(spacing: 6) {
            ForEach(Step.chapters.indices, id: \.self) { chapter in
                Capsule()
                    .fill(WECanvas.cream.ink.opacity(chapter <= index ? 0.78 : 0.12))
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(max(index, 0) + 1) of \(Step.chapters.count)")
        .accessibilityIdentifier("walkthrough.progress")
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .hello: hello
        case .say: say
        case .lands: lands
        case .yours: yours
        case .map: map
        }
    }

    // MARK: Hello

    private var hello: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !typeSize.isAccessibilitySize {
                WelcomeBloom(
                    diameter: 230,
                    identity: setting.identity,
                    formation: arrived || reduceMotion ? 1 : 0.2
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityHidden(true)
            }

            headline(
                helloTitle,
                "One place for the life you share. Here is the whole idea in four moves. You will try each one, and nothing you type is kept."
            )

            VStack(alignment: .leading, spacing: 0) {
                contentsRow(1, "Say it", "Type a thought the way you would text it.")
                contentsRow(2, "It lands", "WE files it, and tells you where and why.")
                contentsRow(3, "Yours or ours", "Share now, or when it\u{2019}s ready.")
                contentsRow(4, "Two places", "Today and Life. That is the whole map.")
                rule
            }
        }
    }

    private var helloTitle: String {
        guard setting.isFirstRun else { return "How WE works." }
        if let name = setting.firstName, !name.isEmpty {
            return "Welcome in, \(name)."
        }
        return "Welcome in."
    }

    private func contentsRow(_ number: Int, _ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            rule
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(String(format: "%02d", number))
                    .font(FieldType.mark)
                    .tracking(FieldTracking.mark)
                    .foregroundStyle(.fieldInk(.label))
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(FieldType.cardTitle)
                    Text(line)
                        .font(FieldType.reasoning)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 15)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 01 Say it

    private var say: some View {
        VStack(alignment: .leading, spacing: 26) {
            chapter(1, "Say it")
            headline(
                "Say it like you\u{2019}d text it.",
                "No lists to pick, no folders to choose. Type a thought, and WE works out where it belongs."
            )
            composer
            suggestions
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .imageScale(.small)
                Text("PRACTICE \u{00B7} NOTHING IS SAVED")
                    .font(FieldType.subLabel)
                    .tracking(FieldTracking.subLabel)
            }
            .foregroundStyle(.fieldInk(.label))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Practice. Nothing is saved.")

            TextField("What\u{2019}s on your mind?", text: $draft, axis: .vertical)
                .font(FieldType.captureWriting)
                .lineLimit(2...5)
                .focused($composing)
                .tint(setting.identity.personA.deep)
                .accessibilityIdentifier("walkthrough.composer")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            WECanvas.cream.bgElevated,
            in: RoundedRectangle(cornerRadius: FirstRunMetrics.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FirstRunMetrics.radius, style: .continuous)
                .strokeBorder(
                    WECanvas.cream.ink.opacity(composing ? 0.30 : 0.10),
                    lineWidth: 1
                )
        )
        .shadow(color: WECanvas.cream.ink.opacity(0.06), radius: 18, y: 10)
        .contentShape(Rectangle())
        .onTapGesture { composing = true }
        .animation(motion, value: composing)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OR BORROW ONE")
                .font(FieldType.subLabel)
                .tracking(FieldTracking.subLabel)
                .foregroundStyle(.fieldInk(.label))
                .padding(.bottom, 6)
            ForEach(WalkthroughPractice.suggestions, id: \.self) { line in
                rule
                Button {
                    withAnimation(motion) { draft = line }
                } label: {
                    HStack(spacing: 12) {
                        Text(line)
                            .font(FieldType.listItem)
                            .foregroundStyle(
                                .fieldInk(trimmedDraft == line ? .headline : .cardProse)
                            )
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: trimmedDraft == line ? "checkmark" : "arrow.up.left")
                            .imageScale(.small)
                            .foregroundStyle(.fieldInk(.label))
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Puts this in the practice box")
            }
            rule
        }
    }

    // MARK: 02 It lands

    private var lands: some View {
        VStack(alignment: .leading, spacing: 26) {
            chapter(2, "It lands")
            headline(
                "Filed. And it tells you where.",
                "Every thought gets a home in Life, a day if you named one, and a line on why it went there."
            )
            if let receipt {
                said(receipt.input)
                WalkthroughSpecimen(
                    receipt: receipt,
                    identity: setting.identity,
                    audience: nil
                )
                correction(for: receipt)
            }
        }
    }

    private func said(_ input: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("YOU SAID")
                .font(FieldType.subLabel)
                .tracking(FieldTracking.subLabel)
                .foregroundStyle(.fieldInk(.label))
            Text("\u{201C}\(input)\u{201D}")
                .font(FieldType.anchorQuote)
                .foregroundStyle(.fieldInk(.reasoning))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func correction(for receipt: FieldReceipt) -> some View {
        let moved = receipt.category != original?.category
        return VStack(alignment: .leading, spacing: 12) {
            Text(moved
                 ? "Moved. In your real Life, WE learns from this, so the next one lands right."
                 : "Wrong home? Tap another and move it.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.reasoning))
                .fixedSize(horizontal: false, vertical: true)
                .id(moved)
                .transition(.opacity)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categoryChoices) { category in
                        Button(category.word) { move(to: category) }
                            .buttonStyle(
                                WalkthroughChipStyle(
                                    isSelected: category == receipt.category,
                                    accent: setting.identity.personA.deep
                                )
                            )
                            .accessibilityAddTraits(
                                category == receipt.category ? .isSelected : []
                            )
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .accessibilityIdentifier("walkthrough.categories")
        }
    }

    private var categoryChoices: [LifeCategory] {
        var choices = LifeCategory.builtIn
        if let first = original?.category, !choices.contains(first) {
            choices.insert(first, at: 0)
        }
        return choices
    }

    // MARK: 03 Yours or ours

    private var yours: some View {
        VStack(alignment: .leading, spacing: 26) {
            chapter(3, "Yours or ours")
            headline(
                "Some things aren\u{2019}t ready yet.",
                "What you add is shared with \(setting.partnerWord) by default. Only me is for the rest: a gift idea, a surprise, something you\u{2019}re still thinking through."
            )
            visibilityPicker
            if let receipt {
                WalkthroughSpecimen(
                    receipt: receipt,
                    identity: setting.identity,
                    audience: isPrivate
                        ? .onlyMe
                        : .both(partner: setting.partnerWord)
                )
            }
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Share it when it\u{2019}s ready, or pick a day and WE will ask you then. WE never shares anything on its own.")
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
                Label {
                    Text("Pairing never opens what you have kept to yourself.")
                } icon: {
                    Image(systemName: "lock")
                }
            }
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.reasoning))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var visibilityPicker: some View {
        HStack(spacing: 4) {
            segment("Both of us", symbol: "person.2", selected: !isPrivate) {
                isPrivate = false
            }
            .accessibilityIdentifier("walkthrough.visibility.shared")
            segment("Only me", symbol: "lock", selected: isPrivate) {
                isPrivate = true
            }
            .accessibilityIdentifier("walkthrough.visibility.private")
        }
        .padding(4)
        .background(
            WECanvas.cream.ink.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func segment(
        _ title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(motion) { action() }
        } label: {
            Label(title, systemImage: symbol)
                .font(FieldType.button)
                .foregroundStyle(.fieldInk(selected ? .headline : .reasoning))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WECanvas.cream.bgElevated)
                            .shadow(color: WECanvas.cream.ink.opacity(0.10), radius: 6, y: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 04 Two places

    private var map: some View {
        VStack(alignment: .leading, spacing: 26) {
            chapter(4, "Two places")
            headline(
                "Two places. That\u{2019}s the whole map.",
                "Nothing to set up and no menus to learn. What you just said is already in both."
            )

            WalkthroughTile(glow: glowColors) {
                zoneHeader("TODAY", "What matters now.")
                zoneLine("One thing worth doing, what you both added, and + to say anything.")
                if let receipt {
                    todayRow(receipt)
                }
            }

            WalkthroughTile(glow: glowColors) {
                zoneHeader("LIFE", "Everything you\u{2019}re carrying.")
                zoneLine("Sorted for you, with search, a calendar for anything dated, and where you\u{2019}re headed together.")
                lifeRows
            }

            if setting.handoff == .invite {
                Text("WE is made for two. Bring in \(setting.partnerWord) and all of this becomes shared.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)
            } else if setting.handoff == .waiting {
                Text("Your invitation is out. Start adding things now, and they will be waiting when \(setting.partnerWord) arrives.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var glowColors: [Color] {
        isPrivate
            ? [setting.identity.personA.soft]
            : [setting.identity.personA.soft, setting.identity.personB.soft]
    }

    private func zoneHeader(_ label: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(FieldType.zoneLabel)
                .tracking(FieldTracking.zoneLabel)
                .foregroundStyle(.fieldInk(.label))
            Text(title)
                .font(FieldType.pageHeadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func zoneLine(_ line: String) -> some View {
        Text(line)
            .font(FieldType.reasoning)
            .foregroundStyle(.fieldInk(.cardProse))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func todayRow(_ receipt: FieldReceipt) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(setting.identity.personA.soft)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(receipt.title)
                .font(FieldType.listItemLarge)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let due = displayedDue(receipt) {
                Text(due, format: .dateTime.weekday(.abbreviated))
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .textCase(.uppercase)
                    .foregroundStyle(.fieldInk(.dateCount))
            }
        }
        .padding(.top, 6)
    }

    private var lifeRows: some View {
        let filed = receipt?.category
        let candidates: [LifeCategory?] = [
            filed, LifeCategory.care, LifeCategory.trips, LifeCategory.home,
        ]
        var rows: [LifeCategory] = []
        for case let category? in candidates where !rows.contains(category) {
            rows.append(category)
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.prefix(3))) { category in
                Rectangle().fill(FieldRule.row).frame(height: 1)
                HStack(alignment: .firstTextBaseline) {
                    Text(category.word)
                        .font(FieldType.listItemLarge)
                        .foregroundStyle(.fieldInk(category == filed ? .headline : .quietListItem))
                    Spacer()
                    Text(category == filed ? "1 NEW" : "")
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(.fieldInk(.dateCount))
                }
                .padding(.vertical, 11)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Shared pieces

    private func headline(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(
                    typeSize.isAccessibilitySize
                        ? .system(.title, design: .serif)
                        : FieldType.hero
                )
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .accessibilityIdentifier("walkthrough.heading")
            Text(subtitle)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.reasoning))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chapter(_ number: Int, _ name: String) -> some View {
        Text(String(format: "%02d", number) + "  \u{00B7}  " + name.uppercased())
            .font(FieldType.mark)
            .tracking(FieldTracking.mark)
            .foregroundStyle(.fieldInk(.label))
            .padding(.top, 10)
            .accessibilityLabel("Part \(number) of 4, \(name)")
    }

    private var rule: some View {
        Rectangle().fill(FieldRule.row).frame(height: 1)
    }

    private func displayedDue(_ receipt: FieldReceipt) -> Date? {
        receipt.category.carriesDates ? receipt.dueOn : nil
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: primary) {
                HStack(spacing: 10) {
                    Text(primaryTitle)
                    Image(systemName: step == .say ? "arrow.down" : "arrow.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(FirstRunPrimaryButtonStyle())
            .disabled(step == .say && trimmedDraft.isEmpty)
            .accessibilityIdentifier("walkthrough.next")
        }
        .frame(maxWidth: FirstRunMetrics.column)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, FirstRunMetrics.side)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(WECanvas.cream.bg.opacity(0.96))
    }

    private var primaryTitle: String {
        switch step {
        case .hello: return "Show me"
        case .say: return "File it"
        case .lands, .yours: return "Next"
        case .map: return handoffTitle
        }
    }

    private var handoffTitle: String {
        switch setting.handoff {
        case .invite: return "Bring in \(setting.partnerWord)"
        case .waiting: return "Start adding"
        case .open: return "Open WE"
        case .replay: return "Done"
        }
    }

    private func primary() {
        switch step {
        case .hello: go(to: .say)
        case .say: file()
        case .lands: go(to: .yours)
        case .yours: go(to: .map)
        case .map: onFinish()
        }
    }

    private func back() {
        switch step {
        case .hello: break
        case .say: go(to: .hello, forward: false)
        case .lands: go(to: .say, forward: false)
        case .yours: go(to: .lands, forward: false)
        case .map: go(to: .yours, forward: false)
        }
    }

    private func go(to next: Step, forward: Bool = true) {
        composing = false
        self.forward = forward
        withAnimation(motion) { step = next }
    }

    /// The real classifier, asked about the real week. The date is today's,
    /// so "Friday" means this Friday rather than one in the past.
    private func file() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
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
        original = filed
        receipt = filed
        isPrivate = false
        go(to: .lands)
    }

    private func move(to category: LifeCategory) {
        guard var moved = receipt, moved.category != category,
              let original else { return }
        moved.category = category
        moved.wasCorrected = category != original.category
        moved.reasoning = category == original.category
            ? original.reasoning
            : "You moved this to \(category.word)."
        withAnimation(motion) { receipt = moved }
    }
}

// MARK: - A window into the app

/// A dark tile on the paper: the product, shown as itself.
private struct WalkthroughTile<Content: View>: View {
    var glow: [Color]
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(22)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.fieldInk(.headline))
        .background(alignment: .bottom) { edgeLight }
        .background(WECanvas.ground.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: FirstRunMetrics.radius, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 22, y: 14)
        .environment(\.weCanvas, .ground)
        .environment(\.colorScheme, .dark)
    }

    /// Light from under the bottom edge, in the colour of whoever can see it.
    /// One person's colour for Only me; both for shared.
    private var edgeLight: some View {
        let colors = glow.count > 1 ? glow : [glow.first ?? .clear, glow.first ?? .clear]
        return ZStack(alignment: .bottom) {
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .frame(height: 70)
                .blur(radius: 28)
                .opacity(0.45)
                .offset(y: 40)
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .frame(height: 2)
        }
        .accessibilityHidden(true)
    }
}

/// The filed thought, the way Life will hold it.
private struct WalkthroughSpecimen: View {
    enum Audience: Equatable {
        case both(partner: String)
        case onlyMe
    }

    let receipt: FieldReceipt
    let identity: FieldIdentity
    let audience: Audience?

    private var glow: [Color] {
        audience == .onlyMe
            ? [identity.personA.soft]
            : [identity.personA.soft, identity.personB.soft]
    }

    var body: some View {
        WalkthroughTile(glow: glow) {
            HStack(alignment: .firstTextBaseline) {
                Text(receipt.category.label)
                    .font(FieldType.subLabel)
                    .tracking(FieldTracking.subLabel)
                    .foregroundStyle(.fieldInk(.label))
                    .contentTransition(.opacity)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                    .foregroundStyle(.fieldInk(.label))
                    .accessibilityHidden(true)
            }

            Text(receipt.title)
                .font(FieldType.pageHeadline)
                .fixedSize(horizontal: false, vertical: true)

            if receipt.category.carriesDates, let due = receipt.dueOn {
                Label {
                    Text(due, format: .dateTime.weekday(.wide).month(.wide).day())
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.cardProse))
                .transition(.opacity)
            }

            Rectangle().fill(FieldRule.row).frame(height: 1)

            if let audience {
                audienceRow(audience)
            } else {
                Text(receipt.reasoning)
                    .font(FieldType.reasoning)
                    .italic()
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("walkthrough.savedItem")
    }

    @ViewBuilder
    private func audienceRow(_ audience: Audience) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(identity.personB.soft)
                    .frame(width: 10, height: 10)
                    .offset(x: 6)
                    .opacity(audience == .onlyMe ? 0 : 1)
                Circle()
                    .fill(identity.personA.soft)
                    .frame(width: 10, height: 10)
                    .offset(x: audience == .onlyMe ? 0 : -1)
            }
            .frame(width: 20, alignment: .leading)
            .accessibilityHidden(true)

            switch audience {
            case .both(let partner):
                Text("You and \(partner)")
                    .font(FieldType.body)
                Spacer()
                Text("SHARED")
                    .font(FieldType.subLabel)
                    .tracking(FieldTracking.subLabel)
                    .foregroundStyle(.fieldInk(.label))
            case .onlyMe:
                Text("Only you, for now")
                    .font(FieldType.body)
                Spacer()
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                    .foregroundStyle(.fieldInk(.label))
            }
        }
        .transition(.opacity)
    }
}

/// A category you can move a thought to.
private struct WalkthroughChipStyle: ButtonStyle {
    let isSelected: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FieldType.button)
            .foregroundStyle(isSelected ? WECanvas.cream.bg : WECanvas.cream.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(
                Capsule().fill(isSelected ? accent : WECanvas.cream.bgElevated)
            )
            .overlay(
                Capsule().strokeBorder(
                    WECanvas.cream.ink.opacity(isSelected ? 0 : 0.14),
                    lineWidth: 1
                )
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
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
                line: "WE would rather say nothing than invent an example."
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
