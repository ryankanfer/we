//
//  TodayView.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct TodayView: View {
    var body: some View {
        ZStack {
            Color("WEBackground")
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    greeting

                    section("TODAY TOGETHER") {
                        TodayTogetherCard()
                    }

                    DateNightCard()

                    section("WHAT NEEDS US") {
                        InsightCard(insight: PreviewData.insight)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Good evening, Ry.")
                .font(.weLargeTitle)
                .foregroundStyle(Color("WEInk"))

            Text("You and Alex, today.")
                .font(.system(size: 14))
                .foregroundStyle(Color("WEFaint"))
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.weCaption)
                .foregroundStyle(Color("WEFaint"))

            content()
        }
    }
}

#Preview {
    NavigationStack {
        TodayView()
    }
}
