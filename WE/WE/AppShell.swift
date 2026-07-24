//
//  AppShell.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct AppShell: View {
    @State private var presentedAction: WEAction?
    @State private var showsWESpace = false

    var body: some View {
        NavigationStack {
            TodayView {
                showsWESpace = true
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActionDock { action in
                presentedAction = action
            }
        }
        .sheet(item: $presentedAction) { action in
            WEActionSheet(action: action)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsWESpace) {
            WESpaceView()
        }
        .tint(Color("WEBurgundy"))
    }
}
