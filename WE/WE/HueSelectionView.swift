//
//  HueSelectionView.swift
//  WE
//
//  Changing your colour, later.
//
//  What was here was three more views: a first run `HueOnboardingView`, a
//  swipeable `HueSelector` of ten colour circles, and a `HueAtmosphere`
//  backdrop. All three were unreachable — the Field cutover moved first run
//  onto `FieldOnboardingView` and colour onto `FieldSwatchRow` — and all
//  three carried the devices the direction removes: step numerals reading
//  "01" and "02", tracked uppercase eyebrows reading "YOUR COLOUR" and "OUR
//  ATMOSPHERE", and a picker made of boxes.
//
//  They are deleted rather than restyled. Only `HueSettingsView` was live,
//  reached from `ProfileView` under Appearance, and it is the same control
//  the rest of the app already has, so it is now the same control: one
//  `FieldSwatchRow`, eight family names in the serif.
//

import SwiftUI

struct HueSettingsView: View {
    @EnvironmentObject private var session: AppSession

    var personalName = "You"
    var partnerName = "your partner"

    /// The two people, as the Field vocabulary sees them.
    ///
    /// `couple_members.hue` is an older and separate enum, so this is a
    /// bridge rather than a read: the person's stored hue maps to its nearest
    /// family, they choose in families, and the choice is written back
    /// through `memberHue`. Two vocabularies is one too many and collapsing
    /// them is a migration for another day, but the *person* should only ever
    /// meet one of them.
    private var identity: FieldIdentity {
        FieldIdentity(
            personA: FieldSwatch(nearest: personalHue),
            personB: FieldSwatch(nearest: partnerHue),
            nameA: personalName,
            nameB: partnerName
        )
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var partnerHue: WEHue {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let member = snapshot.members.first(
                where: { $0.id != user.id }
              ) else {
            return .partnerDefault
        }
        return WEHue(member.hue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WEDisplayText("Anything of yours will be this colour.",
                              role: .majorQuestion)
                    .padding(.bottom, 14)

                Text("Only you choose this.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .padding(.bottom, 34)

                FieldSwatchRow(owner: .a, identity: identity) { swatch in
                    Task { await session.updateHue(swatch.memberHue) }
                }
                .disabled(!session.canMutate || session.isWorking)

                SessionMessageView()
                    .padding(.top, 20)

                Spacer(minLength: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FieldMetrics.usSide)
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack(alignment: .bottom) {
                WECanvas.ground.bg.ignoresSafeArea()

                // The shared atmosphere, where it lives everywhere else in
                // the app: at the bottom edge, as light. It used to be a
                // 360pt generative form in the middle of the page under an
                // eyebrow announcing it, which is a diagram of a blend rather
                // than a blend.
                WEColourField(state: .shared, identity: identity, height: 168)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .environment(\.weCanvas, .ground)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: personalHue)
    }
}

extension FieldSwatch {
    /// The family nearest an older `WEHue`.
    ///
    /// Lossy in one direction on purpose: ten hues map onto eight families,
    /// and the two vocabularies were never in correspondence. What matters is
    /// that a person's existing colour opens on something recognisably theirs
    /// rather than on a default.
    init(nearest hue: WEHue) {
        self = switch hue {
        case .burgundy: .burgundy
        case .blush: .rose
        case .ember: .rust
        case .clay: .rust
        case .plum: .indigo
        case .tide: .teal
        case .mist: .indigo
        case .pearl: .sage
        case .sage: .sage
        case .celadon: .moss
        }
    }
}
