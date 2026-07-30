import SwiftUI

struct SoftStartView: View {
    @EnvironmentObject private var coordinator: SoftStartCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAccount = false
    @State private var confirmsDeletion = false

    var body: some View {
        ZStack {
            WEJourneyBackdrop(
                state: visualState,
                showsContinuityLine: false
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    Spacer(minLength: 28)
                    content
                    Spacer(minLength: 24)
                    accountLink
                }
                .frame(maxWidth: 520, minHeight: 700, alignment: .topLeading)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .scrollIndicators(.hidden)
        }
        .animation(
            .weSettle(duration: 0.4, reduceMotion: reduceMotion),
            value: coordinator.stage
        )
        .sheet(isPresented: $showsAccount) {
            SignInView()
        }
        .confirmationDialog(
            "Delete this private proposal?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete and start again", role: .destructive) {
                coordinator.clear()
            }
            Button("Keep proposal", role: .cancel) {}
        } message: {
            Text("The note and proposal will be removed from this iPhone.")
        }
        .preferredColorScheme(
            visualState == .privateState ? .dark : .light
        )
    }

    private var visualState: WEJourneyState {
        switch coordinator.stage {
        case .capture, .preparing, .proposal:
            .privateState
        case .offerPreview:
            .offerPreview
        }
    }

    private var palette: WEJourneyPalette {
        .palette(for: visualState)
    }

    private var header: some View {
        HStack {
            Text("WE")
                .font(.weMeta)
                .tracking(2)
                .foregroundStyle(palette.secondaryInk)
            Spacer()
            Label("On this iPhone", systemImage: "lock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.secondaryInk)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.stage {
        case .capture:
            capture
                .transition(.opacity)
        case .preparing:
            preparing
                .transition(.opacity)
        case .proposal:
            proposal
                .transition(.opacity)
        case .offerPreview:
            offerPreview
                .transition(.opacity)
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Begin with\none thing")
                .font(.weLargeTitle)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Leave a thought in your own words. WE will prepare one small, reversible proposal on this iPhone.")
                .font(.weBody)
                .foregroundStyle(palette.secondaryInk)

            WEContinuityLine(state: .privateState)
                .frame(height: 28)
                .accessibilityHidden(true)

            ZStack(alignment: .topLeading) {
                if coordinator.note.isEmpty {
                    Text("For example: I would love a quieter Friday.")
                        .font(.body)
                        .foregroundStyle(Color.wePearl.opacity(0.58))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 22)
                        .accessibilityHidden(true)
                }

                TextEditor(text: $coordinator.note)
                    .font(.body)
                    .foregroundStyle(Color.wePearl)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .padding(14)
                    .accessibilityLabel("Private thought")
                    .accessibilityHint(
                        "Enter one thought to prepare a proposal on this iPhone."
                    )
                    .accessibilityIdentifier("softStart.input")
            }
            .background(
                Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.weChampagne.opacity(0.7), lineWidth: 1)
            }

            Label(
                "This stays on this iPhone. Nothing crosses until you approve the exact offer.",
                systemImage: "iphone.gen3"
            )
            .font(.footnote)
            .foregroundStyle(palette.secondaryInk)

            errorNotice

            Button("Prepare one proposal") {
                Task { await coordinator.prepare() }
            }
            .buttonStyle(WEJourneyPrimaryButtonStyle(state: .privateState))
            .disabled(
                coordinator.note
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            )
            .accessibilityIdentifier("softStart.prepare")
        }
    }

    private var preparing: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Preparing this\non your side")
                .font(.weLargeTitle)
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)

            WEContinuityLine(state: .privateState)
                .frame(height: 28)
                .accessibilityHidden(true)

            if reduceMotion {
                Label("Preparing a private proposal", systemImage: "hourglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.ink)
            } else {
                ProgressView()
                    .tint(.weChampagne)
                    .accessibilityLabel("Preparing a private proposal")
            }
            Text("Your note is not sent to WE’s servers or to your partner.")
                .font(.weBody)
                .foregroundStyle(palette.secondaryInk)
        }
    }

    @ViewBuilder
    private var proposal: some View {
        if let proposal = coordinator.proposal {
            VStack(alignment: .leading, spacing: 18) {
                Text("One thing you\ncould protect")
                    .font(.weLargeTitle)
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 10) {
                    Text(proposal.title)
                        .font(.weTitle)
                        .foregroundStyle(palette.ink)

                    WEContinuityLine(state: .privateState)
                        .frame(height: 28)
                        .accessibilityHidden(true)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)

                Label(
                    provenance(for: proposal),
                    systemImage: "apple.intelligence"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryInk)

                Text("It remains private unless you approve an offer.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryInk)

                errorNotice

                Button("Keep on my side") {
                    if coordinator.prepareAccountHandoff(
                        for: .keepPrivateProposal
                    ) {
                        showsAccount = true
                    }
                }
                .buttonStyle(WEJourneyPrimaryButtonStyle(state: .privateState))
                .accessibilityIdentifier("proposal.keep")
                .accessibilityHint("Opens account setup.")

                Button("Offer a topic") {
                    coordinator.showOfferPreview()
                }
                .buttonStyle(
                    WEJourneySecondaryButtonStyle(state: .privateState)
                )
                .accessibilityIdentifier("proposal.offer")

                Button("Delete and start again", role: .destructive) {
                    confirmsDeletion = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryInk)
                .frame(minHeight: 44)
                .accessibilityHint(
                    "Removes the note and proposal from this iPhone."
                )
            }
        }
    }

    @ViewBuilder
    private var offerPreview: some View {
        if let proposal = coordinator.proposal {
            let topic = proposal.offeredTopic
            VStack(alignment: .leading, spacing: 18) {
                Button {
                    coordinator.showProposal()
                } label: {
                    Label("Your proposal", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryInk)
                .frame(minHeight: 44)

                Text("Offer only this")
                    .font(.weLargeTitle)
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 10) {
                    Text(topic.title)
                        .font(.weTitle)
                        .foregroundStyle(palette.ink)
                    Text(topic.question)
                        .font(.weBody)
                        .foregroundStyle(palette.secondaryInk)
                    Text(topic.options.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryInk)
                }
                .padding(.vertical, 20)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.weChampagne)
                        .frame(width: 1)
                }

                Text("Your partner will see this topic and these choices—not your note or private proposal.")
                    .font(.weBody)
                    .foregroundStyle(palette.secondaryInk)

                VStack(alignment: .leading, spacing: 5) {
                    Label("Prepared by WE", systemImage: "sparkles")
                    Label(
                        "Approval happens when you continue",
                        systemImage: "hand.raised"
                    )
                }
                .font(.footnote)
                .foregroundStyle(palette.secondaryInk)

                errorNotice

                Button("Keep this offer") {
                    if coordinator.prepareAccountHandoff(
                        for: .offerApprovedTopic
                    ) {
                        showsAccount = true
                    }
                }
                .buttonStyle(WEJourneyPrimaryButtonStyle(state: .offerPreview))
                .accessibilityIdentifier("offer.confirm")
                .accessibilityHint("Opens account setup.")
            }
        }
    }

    private var accountLink: some View {
        Button("I already have WE") {
            showsAccount = true
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(palette.secondaryInk)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    @ViewBuilder
    private var errorNotice: some View {
        if let errorMessage = coordinator.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(palette.ink)
                .accessibilityLabel(
                    "Could not save proposal. \(errorMessage)"
                )
        }
    }

    private func provenance(for proposal: PrivateProposal) -> String {
        switch proposal.preparationMethod {
        case .onDeviceModel:
            "Prepared on this iPhone from this note."
        case .deterministicFallback:
            "Prepared on this iPhone without the on-device model."
        }
    }
}

#Preview {
    SoftStartView()
        .environmentObject(SoftStartCoordinator())
}
