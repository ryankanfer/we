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
    /// How many separate things point at this. Never shown as a number.
    var weight: Int
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
    static func mentions(in state: FieldState) -> [FieldMention] {
        var result: [FieldMention] = []

        for horizon in state.horizons {
            // The things in Life pointing at it, plus the evidence that says
            // an ordinary week moved it. Both are already stored links, so
            // this counts facts rather than guessing at language.
            let linked = horizon.linkedLifeItemIDs.count
            let evidence = state.evidence.count { $0.horizonID == horizon.id }
            result.append(
                FieldMention(
                    id: "horizon-\(horizon.id)",
                    text: horizon.title,
                    kind: .horizon,
                    owner: horizon.owner,
                    weight: linked + evidence,
                    provenance: horizon.window
                )
            )
        }

        for rhythm in state.rhythms {
            result.append(
                FieldMention(
                    id: "rhythm-\(rhythm.id)",
                    text: rhythm.title,
                    kind: .rhythm,
                    owner: .shared,
                    weight: rhythm.occurrences,
                    provenance: rhythm.cadence
                )
            )
        }

        for anchor in state.anchors {
            // Agreed once, and not up for discussion again. It belongs on the
            // screen — it is part of what the couple is — but it is not
            // something that keeps coming up, so it sits at the floor.
            result.append(
                FieldMention(
                    id: "anchor-\(anchor.id)",
                    text: anchor.text,
                    kind: .anchor,
                    owner: .shared,
                    weight: 1,
                    provenance: nil
                )
            )
        }

        // Heaviest first, then by text so the field is stable across launches
        // rather than reordering on a dictionary's whim.
        return result.sorted {
            $0.weight == $1.weight
                ? $0.text < $1.text
                : $0.weight > $1.weight
        }
    }

    /// Which of the five steps a mention sits at, by its rank in the field.
    ///
    /// Rank rather than raw weight, deliberately. A couple whose heaviest
    /// thing has been mentioned four times and one whose heaviest has been
    /// mentioned forty times should both get a readable field; keying the
    /// sizes to absolute counts would give the first a page of uniformly tiny
    /// words and the second one enormous word and nothing else.
    static func step(forRank rank: Int, of total: Int) -> Int {
        guard total > 1 else { return 0 }
        // The top item always gets the top step; the rest spread across what
        // is left, so a field of three does not skip straight to the floor.
        let span = min(total, sizes.count)
        let scaled = Double(rank) / Double(max(total - 1, 1))
        return min(sizes.count - 1, Int(scaled * Double(span - 1) + 0.5))
    }
}

// MARK: - The surface

struct FieldUsFieldSurface: View {
    @Environment(FieldStore.self) private var store

    private var mentions: [FieldMention] {
        FieldUsMentions.mentions(in: store.state)
    }

    var body: some View {
        let mentions = self.mentions

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
                    let step = FieldUsMentions.step(
                        forRank: index,
                        of: mentions.count
                    )

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mention.text)
    }
}
