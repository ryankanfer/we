//
//  AppShell.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct AppShell: View {
    var body: some View {
        TabView {
            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("Today", systemImage: "sun.max.fill")
            }

            PlaceholderView(title: "Plan", symbol: "calendar")
                .tabItem {
                    Label("Plan", systemImage: "calendar")
                }

            PlaceholderView(title: "Home", symbol: "house")
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            PlaceholderView(title: "Profile", symbol: "person")
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
        }
        .tint(Color("WEBurgundy"))
    }
}

private struct PlaceholderView: View {
    let title: String
    let symbol: String

    var body: some View {
        ZStack {
            Color("WEBackground").ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.largeTitle)

                Text(title)
                    .font(.weTitle)
            }
            .foregroundStyle(Color("WEInk"))
        }
    }
}