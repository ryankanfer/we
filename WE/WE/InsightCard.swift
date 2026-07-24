//
//  InsightCard.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct InsightCard: View {
    let insight: Insight

    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(insight.title)
                .font(.weTitle)
                .foregroundStyle(Color("WEInk"))

            Text(insight.body)
                .font(.weBody)
                .foregroundStyle(Color("WEFaint"))

            Button {
                showsDetail = true
            } label: {
                HStack {
                    Text(insight.actionTitle)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.weHeadline)
                .foregroundStyle(Color("WEBurgundy"))
                .frame(minHeight: 44)
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
        .sheet(isPresented: $showsDetail) {
            InsightDetailView(insight: insight)
        }
    }
}

private struct InsightDetailView: View {
    let insight: Insight

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(insight.title)
                        .font(.weLargeTitle)

                    Text(insight.evidence)
                        .font(.weBody)
                        .foregroundStyle(Color("WEFaint"))

                    VStack(spacing: 10) {
                        ForEach(insight.options, id: \.self) { option in
                            Button(option) {}
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color("WEBackground"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
