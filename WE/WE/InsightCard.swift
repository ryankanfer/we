//
//  InsightCard.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct InsightCard: View {
    let insight: Insight

    @State private var isOpened = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(insight.title)
                .font(.weTitle)
                .foregroundStyle(Color("WEInk"))

            Text(insight.body)
                .font(.weBody)
                .foregroundStyle(Color("WEFaint"))
                .lineSpacing(3)

            Divider()
                .overlay(Color("WELine"))

            Button {
                withAnimation {
                    isOpened.toggle()
                }
            } label: {
                HStack {
                    Text(isOpened ? "Opened for preview" : "Open together")
                    Spacer()
                    Image(systemName: isOpened ? "checkmark" : "arrow.right")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color("WEBurgundy"))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            Color("WECard"),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color("WELine"))
        }
    }
}