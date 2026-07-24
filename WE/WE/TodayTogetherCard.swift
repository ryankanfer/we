//
//  TodayTogetherCard.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct TodayTogetherCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AT A GLANCE")
                .font(.weCaption)
                .foregroundStyle(.white.opacity(0.6))

            glanceRow("2 events today", symbol: "calendar")
            glanceRow("1 task together", symbol: "checkmark.circle")
            glanceRow("Dinner at 7:00", symbol: "fork.knife")
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color("WEInk"),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private func glanceRow(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.weBody)
    }
}
