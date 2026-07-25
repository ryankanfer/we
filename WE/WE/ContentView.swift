//
//  ContentView.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color("WEBackground"))
        case .unconfigured:
            BackendStateView(
                title: "Connect WE to Supabase.",
                message: """
                Add SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY to the \
                WE scheme, or set WE_REPOSITORY to preview.
                """
            )
        case .signedOut:
            SignInView()
        case .needsCouple:
            BackendStateView(
                title: "Your account is ready.",
                message: """
                This account does not have a couple membership yet. \
                Create or join a shared space in the web prototype, \
                then reopen WE.
                """,
                retry: {
                    Task { await session.retry() }
                },
                signOut: {
                    Task { await session.signOut() }
                }
            )
        case .ready:
            AppShell()
        case .failed(let message):
            BackendStateView(
                title: "WE could not load.",
                message: message,
                retry: {
                    Task { await session.retry() }
                },
                signOut: {
                    Task { await session.signOut() }
                }
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(
            AppSession(repository: PreviewRepository())
        )
}
