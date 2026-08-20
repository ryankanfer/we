//
//  FieldJourneyRoom.swift
//  WE
//
//  The room behind a living journey.
//
//  Us keeps showing one thing at a time — a question, a proposal, the journey
//  itself. This is where a journey that has been running for a while can be
//  opened, and where the views it has grown are drawn.
//
//  The composition rule worth preserving: the body is an exhaustive switch
//  over a closed enum, not a lookup in a registry. A capability cannot appear
//  here without a Swift file that draws it and a review that let it in. That
//  constraint is the reason this can be adaptive without being unpredictable.
//

import SwiftUI

struct FieldJourneyRoom: View {
    let journey: SharedJourney
    @EnvironmentObject private var session: AppSession
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var provenance: FieldProvenance?
    @State private var showsHelp = false
    @State private var confirmingEnd = false

    private var bindings: [JourneyCapabilityBinding] {
        SharedJourneyCapabilityPolicy.eligible(
            for: journey, context: store.sharedPresenceContext
        )
    }

    /// Surfaces put away that would come back if taken up.
    private var setDown: [JourneyCapability] {
        SharedJourneyCapabilityPolicy.setDown(
            for: journey, context: store.sharedPresenceContext
        )
    }

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if bindings.isEmpty {
                        stillTakingShape
                    } else {
                        ForEach(bindings) { binding in
                            FieldRuleLine()
                                .padding(.vertical, 30)
                            capability(binding)
                        }
                    }
                    FieldRuleLine()
                        .padding(.vertical, 30)
                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 48)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.legend))
                .padding(.top, 20)
                .padding(.trailing, FieldMetrics.screenSide)
        }
        .sheet(item: $provenance) { proof in
            FieldProvenanceSheet(provenance: proof)
                .environment(store)
        }
        .sheet(isPresented: $showsHelp) {
            FieldJourneyGrowthHelp()
        }
        .task {
            store.markEarned(
                SharedJourneyCapabilityPolicy.newlyEarned(
                    for: journey, context: store.sharedPresenceContext
                )
            )
        }
        // Recorded on the way out, not on arrival.
        //
        // `isFirst` below reads `hasBeenTaught` live, so teaching it during the
        // visit would delete the explanation out from under the person while
        // they were still reading it. Marking it as they leave means the whole
        // visit is the first visit, and the next one is not.
        .onDisappear {
            if !bindings.isEmpty {
                store.teach(FieldTeaching.firstCapability)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("A shared journey")
                .padding(.bottom, 14)
                .accessibilityIdentifier("field.journey.room")

            Text(journey.title)
                .font(FieldType.horizon)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.06, size: 44)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            Text(journey.summary)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.58, size: 15)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Said plainly rather than drawn as an empty frame.
    ///
    /// A room with placeholder tools in it promises things the couple has not
    /// asked for and the app cannot yet do. Saying nothing has grown here yet
    /// is both true and, unlike a grid of greyed-out icons, not a roadmap.
    private var stillTakingShape: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()
                .padding(.vertical, 30)
            Text("This journey is still taking shape.")
                .font(FieldType.synthesis)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.28, size: 25)
                .fixedSize(horizontal: false, vertical: true)
            Text("Views appear here when there is enough between you to make one useful.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.58, size: 15)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func capability(_ binding: JourneyCapabilityBinding) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch binding.capability {
            case .criteria:
                FieldJourneyCriteriaSurface(
                    journey: journey,
                    isFirst: !store.hasBeenTaught(FieldTeaching.firstCapability)
                )
            // Declared, not yet built. `eligible` never returns these, so this
            // arm is unreachable today — it exists so that building one is a
            // matter of filling in a case rather than finding every switch.
            case .comparison, .schedule, .budgetBand, .checklist:
                EmptyView()
            }

            HStack(spacing: 18) {
                if binding.provenance.isProvable {
                    Button("What brought this here") {
                        provenance = binding.provenance
                    }
                    .buttonStyle(.plain)
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.legend))
                }
                Spacer()
                Button("Set this down") {
                    store.setDown(
                        adaptation: SharedJourneyCapabilityPolicy.key(
                            binding.capability, journey: journey
                        )
                    )
                }
                .buttonStyle(.plain)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.legend))
            }
            .padding(.top, 24)
        }
    }

    /// Taking a surface back up.
    ///
    /// Set-down is couple-wide and persisted, so without this one tap by one
    /// person removed a surface from both people permanently. LIFE has had the
    /// matching gesture all along — `bringBack` and its "Bring back" button —
    /// and the rule is the same here: either of them can, whoever set it down.
    @ViewBuilder
    private var putAway: some View {
        if !setDown.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                FieldLabel("Set down")
                ForEach(setDown, id: \.self) { capability in
                    HStack(spacing: 12) {
                        Text(SharedJourneyCapabilityPolicy.word(capability))
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.sectionSubtitle))
                        Spacer(minLength: 12)
                        Button("Take this back up") {
                            store.takeUp(
                                adaptation: SharedJourneyCapabilityPolicy.key(
                                    capability, journey: journey
                                )
                            )
                        }
                        .buttonStyle(FieldQuietButtonStyle())
                        .accessibilityIdentifier("field.journey.takeUp")
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 18) {
            putAway

            Button("How this journey grows") { showsHelp = true }
                .buttonStyle(.plain)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.legend))

            if confirmingEnd {
                // Named as a request rather than an action, because it is one:
                // the journey closes when the other person says so too.
                Text("This closes when you both close it. Nothing is removed.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.5, size: 13)
            }

            Button(confirmingEnd ? "Yes, I'm ready to close it" : "Close this journey") {
                if confirmingEnd {
                    Task { await session.completeFieldJourney(journeyID: journey.id) }
                    dismiss()
                } else {
                    confirmingEnd = true
                }
            }
            .buttonStyle(.plain)
            .font(FieldType.reasoning)
            .foregroundStyle(.fieldInk(.legend))
        }
    }
}

/// The replayable explanation, kept separate from the first-run one so that
/// asking for it later is not the same surface as being told once.
private struct FieldJourneyGrowthHelp: View {
    @Environment(\.dismiss) private var dismiss

    private let lines = [
        "Views appear here as the things you already share add up to something worth looking at together.",
        "They read what you have already shared. They never read anything private, and nothing appears for one of you and not the other.",
        "Any of them can be set down, and taken back up again from here. Setting one down keeps everything it was reading.",
    ]

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    FieldLabel("How this journey grows")
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.sectionSubtitle))
                            .fieldLineHeight(1.58, size: 15)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Close") { dismiss() }
                        .buttonStyle(.plain)
                        .font(FieldType.reasoning)
                        .foregroundStyle(.fieldInk(.legend))
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 48)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
    }
}
