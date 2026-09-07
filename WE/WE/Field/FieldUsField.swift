//
//  FieldUsField.swift
//  WE
//
//  Us, at rest — a field. Option 14d.
//
//  Every other surface in this app is a column: a heading, then things under
//  it, left-aligned, one per line. That is correct for Life and for Today,
//  where the question is *what is being asked of us and when*. It is wrong
//  here. §2 requires each screen to answer "what kind of object is this?" with
//  an answer no other screen gives, and a list of the things a couple keeps
//  coming back to is indistinguishable from a list of errands.
//
//  So Us is not a list. It is a **field**: words placed across an area, sized
//  by how often each one comes up, with no order to read them in. Nothing here
//  is numbered, dated, checkable or finishable — §4 is explicit that *nothing
//  in Us can be finished*, which is exactly what separates it from Life. A
//  thing leaves this screen by stopping being mentioned, not by being done.
//
//  ## Where the size comes from
//
//  "How often it comes up" is not a new measurement, and deliberately not a
//  new column. It is read off what the couple has already accumulated:
//
//  - a **horizon** is weighted by the Life items linked to it and the evidence
//    that references it — the things they keep doing that point at it
//  - a **rhythm** carries `occurrences` already, which is literally the count
//    of how often it has happened
//  - an **anchor** is something agreed once and not relitigated, so it sits at
//    the floor: present, small, and not clamouring
//
//  Nothing is inferred from language and nothing is counted twice. If a couple
//  has mentioned Japan in nine different ways, what makes "Japan" large here is
//  the nine things in Life pointing at it, each of which they can go and read.
//
//  The header says the rule out loud — `SIZE IS HOW OFTEN IT COMES UP` —
//  because a size that encodes something is a lie if the reader has to guess
//  what. §4 requires it.
//

import SwiftUI

// MARK: - The model

/// One word in the field, and the weight that sizes it.
struct FieldMention: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case horizon
        case rhythm
        case anchor
    }

    let id: String
    var text: String
    var kind: Kind
    var owner: FieldOwner
    /// How many accumulated records point at this. Never shown as a number.
    ///
    /// One unit throughout: *a record the couple already has*. A horizon
    /// counts the distinct shared Life items linked to it plus the evidence
    /// referencing it; a rhythm counts the times it happened; an anchor counts
    /// the one agreement it is. Nothing is inferred from language, nothing is
    /// counted twice, and nothing private is counted at all.
    var weight: Int
    /// The records behind the weight, in the couple's own words, for the
    /// person who taps the word and asks why it is that big.
    ///
    /// Everything in here is already visible to both of them. See
    /// `mentions(in:)` for what that costs.
    var support: [String]
    /// The one line of provenance, carried only by the largest.
    var provenance: String?
}

enum FieldUsMentions {
    /// The five type sizes of §14d, largest first.
    static let sizes: [CGFloat] = [42, 30, 23, 18, 15]
    /// The opacity each step falls to, matched to `sizes`.
    ///
    /// §14d ramps these 1.0 → 0.32. The bottom three would land at 3.35:1 or
    /// worse on this ground, so they are clamped to the ink ramp's AA floor —
    /// the same trade `FieldStrata` makes, and for the same reason. Size is
    /// carrying the hierarchy here anyway, which is the whole point of the
    /// screen: a 15px word beside a 42px one is unmistakably quieter without
    /// needing to be fainter as well.
    static let inks: [FieldInk] = [
        .headline, .secondaryHeading, .legend, .metadataProse, .recessive,
    ]

    /// How far each step may drift off the left margin, so the field reads as
    /// placed rather than as a ragged column.
    ///
    /// §14d gives 0–58px. The offsets are a fixed table rather than random:
    /// this view is re-rendered on every state change, and a field that
    /// reshuffles itself while somebody is reading it would be the most
    /// distracting thing in the app.
    static let offsets: [CGFloat] = [0, 34, 12, 58, 26]

    /// Read the field out of what the couple already has.
    ///
    /// ## What may be counted
    ///
    /// Only records both people can reach. A horizon's `linkedLifeItemIDs` is
    /// a list of ids, and some of those items may be private — solo-era
    /// history its owner has not crossed. Counting them would make a word on a
    /// screen *both* people look at get visibly bigger because of something
    /// only one of them can see, and a size is a channel like any other. The
    /// ids are resolved against `state.lifeItems` and filtered on
    /// `isSharedPresence` before anything is counted, and an id that resolves
    /// to nothing is not counted either — an unresolvable reference is not
    /// evidence.
    ///
    /// Duplicated ids collapse. A horizon that lists the same item twice has
    /// one thing pointing at it, not two.
    static func mentions(in state: FieldState) -> [FieldMention] {
        var result: [FieldMention] = []

        // One pass over Life, so a couple with a long list does not pay for a
        // lookup per link per horizon.
        let shared = state.lifeItems.reduce(into: [String: LifeItem]()) {
            guard $1.isSharedPresence else { return }
            $0[$1.id] = $1
        }

        for horizon in state.horizons {
            // The things in Life pointing at it, plus the evidence that says
            // an ordinary week moved it. Both are already stored links, so
            // this counts facts rather than guessing at language.
            var seen: Set<String> = []
            let linked = horizon.linkedLifeItemIDs.compactMap { id -> String? in
                guard seen.insert(id).inserted,
                      let item = shared[id]
                else { return nil }
                return item.title
            }
            let evidence = state.evidence
                .filter { $0.horizonID == horizon.id }
                .map(\.statement)

            result.append(
                FieldMention(
                    id: "horizon-\(horizon.id)",
                    text: horizon.title,
                    kind: .horizon,
                    owner: horizon.owner,
                    weight: linked.count + evidence.count,
                    support: linked + evidence,
                    provenance: horizon.window
                )
            )
        }

        for rhythm in state.rhythms {
            // The one place the records themselves cannot be listed: a rhythm
            // stores how many times it has happened, not a row per time. So
            // the support says the count in words rather than pretending to
            // enumerate something that was never kept.
            result.append(
                FieldMention(
                    id: "rhythm-\(rhythm.id)",
                    text: rhythm.title,
                    kind: .rhythm,
                    owner: .shared,
                    weight: rhythm.occurrences,
                    support: [
                        rhythm.occurrences == 1
                            ? "It has happened once."
                            : "It has happened \(rhythm.occurrences) times.",
                    ],
                    provenance: rhythm.cadence
                )
            )
        }

        for anchor in state.anchors {
            // Agreed once, and not up for discussion again. It belongs on the
            // screen — it is part of what the couple is — but it is not
            // something that keeps coming up, so it sits at the floor: one
            // record, the agreement itself.
            result.append(
                FieldMention(
                    id: "anchor-\(anchor.id)",
                    text: anchor.text,
                    kind: .anchor,
                    owner: .shared,
                    weight: 1,
                    support: ["Agreed once, and not brought up since."],
                    provenance: nil
                )
            )
        }

        // Heaviest first, then by text so the field is stable across launches
        // rather than reordering on a dictionary's whim.
        //
        // The alphabetical tiebreak decides *reading order only*. It used to
        // decide size as well, because the step was keyed to array index: two
        // subjects with identical evidence rendered at visibly different sizes
        // because of their first letter, under a header promising that size
        // meant frequency. See `steps(for:)`.
        return result.sorted {
            $0.weight == $1.weight
                ? $0.text < $1.text
                : $0.weight > $1.weight
        }
    }

    /// Which step each mention sits at, for a field already in weight order.
    ///
    /// Keyed to the *distinct* weights present rather than to position, which
    /// is what makes the header's claim true: equal evidence, equal size.
    ///
    /// Rank rather than raw weight, deliberately. A couple whose heaviest
    /// thing has been mentioned four times and one whose heaviest has been
    /// mentioned forty times should both get a readable field; keying the
    /// sizes to absolute counts would give the first a page of uniformly tiny
    /// words and the second one enormous word and nothing else. It also means
    /// adding something unrelated cannot resize the whole field — only adding
    /// a *new distinct weight* changes the ramp.
    static func steps(for mentions: [FieldMention]) -> [Int] {
        // One word is not a hierarchy. It gets the top step rather than the
        // middle one, because there is nothing for it to be quieter than.
        guard mentions.count > 1 else { return mentions.map { _ in 0 } }

        // Distinct weights, heaviest first, matching the sort above.
        var distinct: [Int] = []
        for mention in mentions where distinct.last != mention.weight {
            distinct.append(mention.weight)
        }

        return mentions.map { mention in
            let rank = distinct.firstIndex(of: mention.weight) ?? 0
            return step(forDenseRank: rank, ofDistinct: distinct.count)
        }
    }

    /// Which of the five steps a given distinct weight sits at.
    static func step(forDenseRank rank: Int, ofDistinct distinct: Int) -> Int {
        // Nothing distinguishes them, so nothing may be emphasised over
        // anything else — and a whole page at 42px is not "equal", it is
        // shouting. The middle of the ramp is the one honest answer.
        guard distinct > 1 else { return sizes.count / 2 }

        // The heaviest always gets the top step; the rest spread across what
        // is left, so a field of three does not skip straight to the floor.
        let span = min(distinct, sizes.count)
        let scaled = Double(rank) / Double(distinct - 1)
        return min(sizes.count - 1, Int(scaled * Double(span - 1) + 0.5))
    }
}

// MARK: - The surface

struct FieldUsFieldSurface: View {
    @Environment(FieldStore.self) private var store

    /// The word somebody asked about. Nothing is open by default — the field
    /// is a thing to look at before it is a thing to interrogate.
    @State private var asking: FieldMention?

    private var mentions: [FieldMention] {
        FieldUsMentions.mentions(in: store.state)
    }

    var body: some View {
        let mentions = self.mentions
        let steps = FieldUsMentions.steps(for: mentions)

        VStack(alignment: .leading, spacing: 0) {
            // §4: the rule is stated, not left to be inferred.
            FieldLabel(
                "SIZE IS HOW OFTEN IT COMES UP",
                font: FieldType.subLabel,
                tracking: FieldTracking.subLabel,
                ink: .label
            )
            .padding(.bottom, 40)
            .accessibilityIdentifier("field.us.field.rule")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(mentions.enumerated()), id: \.element.id) { index, mention in
                    let step = steps[index]

                    word(mention, step: step, isLead: index == 0)
                        .padding(.leading, FieldUsMentions.offsets[
                            index % FieldUsMentions.offsets.count
                        ])
                        // Tighter as they get smaller, so the field closes up
                        // toward the bottom rather than trailing off evenly.
                        .padding(.bottom, spacing(for: step))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("field.us.field")
        .sheet(item: $asking) { FieldMentionSheet(mention: $0) }
    }

    private func spacing(for step: Int) -> CGFloat {
        switch step {
        case 0: 26
        case 1: 21
        case 2: 17
        case 3: 14
        default: 11
        }
    }

    @ViewBuilder
    private func word(
        _ mention: FieldMention,
        step: Int,
        isLead: Bool
    ) -> some View {
        let size = FieldUsMentions.sizes[step]

        Button {
            asking = mention
        } label: {
            VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(mention.text)
                    .font(FieldType.usFieldSteps[step])
                    .foregroundStyle(.fieldInk(FieldUsMentions.inks[step]))
                    .fieldLineHeight(1.06, size: size)
                    .fixedSize(horizontal: false, vertical: true)

                // Colour only where it means something: whose horizon this is.
                // Rhythms and anchors belong to both by definition, and a dot
                // on every word would turn the field into a legend.
                if mention.kind == .horizon, mention.owner != .shared {
                    FieldDot(
                        owner: mention.owner,
                        identity: store.identity,
                        size: FieldDotSize.chip,
                        baselineNudge: 0
                    )
                }
            }

            // §14d: only the top item carries provenance. Keyed to rank
            // rather than to the step, because more than one word can share
            // the largest step — which is how two lines of provenance got
            // onto the screen the first time this rendered.
            if isLead, let provenance = mention.provenance {
                Text(provenance.uppercased())
                    .font(FieldType.subLabel)
                    .tracking(FieldTracking.subLabel)
                    .foregroundStyle(.fieldInk(.dateCount))
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mention.text)
        .accessibilityHint("Shows what makes this one bigger")
        .accessibilityIdentifier("field.us.field.word")
    }
}

// MARK: - Why that big

/// The records behind one word.
///
/// A size that encodes something is a lie if the reader has to guess what, and
/// the header saying `SIZE IS HOW OFTEN IT COMES UP` is a claim rather than
/// proof of one. This is the proof: the actual things the couple accumulated
/// that point at this subject, in their own words.
///
/// Every line here is already on a screen both of them can open — see
/// `FieldUsMentions.mentions(in:)`, which does the filtering, so that this
/// view cannot be the place where a private item leaks by being explained.
private struct FieldMentionSheet: View {
    let mention: FieldMention
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    FieldLabel("What keeps bringing this up")
                        .padding(.bottom, 16)

                    Text(mention.text)
                        .font(FieldType.listItemLarge)
                        .foregroundStyle(.fieldInk(.headline))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 28)

                    if mention.support.isEmpty {
                        // Honest about the floor. A word with nothing behind
                        // it is on the screen because the couple named it, and
                        // saying so is better than an empty list implying the
                        // records were lost.
                        Text("Nothing else in Life or Us points at this one "
                             + "yet. It is here because you named it.")
                            .font(FieldType.reasoning)
                            .foregroundStyle(.fieldInk(.reasoning))
                            .fieldLineHeight(1.6, size: 14)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(mention.support.enumerated()), id: \.offset) {
                                _, line in
                                Text(line)
                                    .font(FieldType.body)
                                    .foregroundStyle(.fieldInk(.headline))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Spacer(minLength: 40)

                    Button("Close") { dismiss() }
                        .buttonStyle(FieldQuietButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 40)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.us.mention")
    }
}
