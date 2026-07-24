//
//  DateNightCard.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct DateNightCard: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("TOMORROW")
                    .font(.weCaption)
                    .foregroundStyle(.white.opacity(0.6))

                Text("Date night")
                    .font(.weTitle)

                Text("7:00 PM · Nami")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            Image(systemName: "fork.knife")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(
            Color("WEBurgundy"),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }
}