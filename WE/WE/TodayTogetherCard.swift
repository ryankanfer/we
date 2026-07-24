//
//  TodayTogetherCard.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct TodayTogetherCard: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("AT A GLANCE")
                    .font(.weCaption)
                    .foregroundStyle(.white.opacity(0.6))

                Label("2 events today", systemImage: "calendar")
                Label("1 task together", systemImage: "checkmark.circle")
                Label("Dinner at 7:00", systemImage: "fork.knife")
            }
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Color("WEInk"), in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 16) {
                Text("ENERGY")
                    .font(.weCaption)
                    .foregroundStyle(Color("WEFaint"))

                EnergyRow(color: Color("WEBurgundy"), name: "You", state: "Steady")
                EnergyRow(color: Color("WESage"), name: "Alex", state: "Stretched")
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Color("WECard"), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color("WELine"))
            }
        }
    }
}

private struct EnergyRow: View {
    let color: Color
    let name: String
    let state: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(name)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Text(state)
                .font(.system(size: 12))
                .foregroundStyle(Color("WEFaint"))
        }
    }
}