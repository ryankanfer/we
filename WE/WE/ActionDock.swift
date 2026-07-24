//
//  ActionDock.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import SwiftUI

enum WEAction: String, Identifiable {
    case capture
    case ask
    case shape
    case space

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: "Capture"
        case .ask: "Ask WE"
        case .shape: "Shape"
        case .space: "WE"
        }
    }

    var symbol: String {
        switch self {
        case .capture: "plus"
        case .ask: "sparkles"
        case .shape: "wand.and.stars"
        case .space: "circle.grid.2x2"
        }
    }
}

struct ActionDock: View {
    let onSelect: (WEAction) -> Void

    @State private var lastSelected: WEAction?

    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    var body: some View {
        HStack(spacing: 6) {
            actionButton(.capture)
            actionButton(.ask, emphasized: true)
            actionButton(.shape)
        }
        .padding(6)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .sensoryFeedback(.impact(weight: .light), trigger: lastSelected)
    }

    private func actionButton(
        _ action: WEAction,
        emphasized: Bool = false
    ) -> some View {
        Button {
            lastSelected = action
            onSelect(action)
        } label: {
            actionLabel(action)
                .font(.system(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(
                    emphasized ? .white : Color("WEInk")
                )
                .background {
                    if emphasized {
                        Capsule().fill(personalHue.controlColor)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(action.title)")
    }

    @ViewBuilder
    private func actionLabel(_ action: WEAction) -> some View {
        if action == .ask {
            HStack(spacing: 8) {
                WEMark(
                    style: .micro,
                    showsWordmark: false
                )
                .accessibilityHidden(true)

                Text(action.title)
            }
        } else {
            Label(action.title, systemImage: action.symbol)
        }
    }
}
