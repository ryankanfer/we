//
//  WEActionSheet.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct WEActionSheet: View {
    let action: WEAction

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(heading)
                        .font(.weLargeTitle)

                    Text(explanation)
                        .font(.weBody)
                        .foregroundStyle(Color("WEFaint"))

                    content
                }
                .padding(20)
            }
            .background(Color("WEBackground"))
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var heading: String {
        switch action {
        case .capture: "Hold onto something."
        case .ask: "What can WE help with?"
        case .shape: "Let’s make it lighter."
        case .space: "Your shared space."
        }
    }

    private var explanation: String {
        switch action {
        case .capture:
            "Begin privately. You decide if it ever becomes shared."
        case .ask:
            "Ask about your plans, memories, or something still open."
        case .shape:
            "Turn a loose thought or crowded day into a workable next step."
        case .space:
            "One history, organized around the life you are building together."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch action {
        case .capture, .ask:
            TextField("Start here…", text: $draft, axis: .vertical)
                .lineLimit(4...8)
                .padding(16)
                .background(
                    Color("WECard"),
                    in: RoundedRectangle(cornerRadius: 18)
                )

            Button(action == .capture ? "Keep privately" : "Ask WE") {}
                .buttonStyle(.borderedProminent)
                .tint(Color("WEBurgundy"))
                .disabled(draft.isEmpty)

        case .shape:
            InsightCard(insight: PreviewData.insights[0])

        case .space:
            VStack(spacing: 0) {
                spaceRow("Now", symbol: "sun.max")
                spaceRow("Us", symbol: "circle.hexagongrid")
                spaceRow("Life", symbol: "house")
                spaceRow("Plans", symbol: "calendar")
                spaceRow("Memories", symbol: "photo")
                spaceRow("Private reflections", symbol: "lock")
            }
            .background(
                Color("WECard"),
                in: RoundedRectangle(cornerRadius: 22)
            )
        }
    }

    private func spaceRow(_ title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Color("WEFaint"))
        }
        .font(.weBody)
        .foregroundStyle(Color("WEInk"))
        .frame(minHeight: 54)
        .padding(.horizontal, 16)
    }
}