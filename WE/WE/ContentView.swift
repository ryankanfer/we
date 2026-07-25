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
            PairingView()
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

private struct PairingView: View {
    @EnvironmentObject private var session: AppSession
    @State private var joinCode = ""

    var body: some View {
        ZStack {
            Color("WEBackground")
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WEMark(style: .compact)

                    Text("Make this space yours.")
                        .font(.weLargeTitle)
                        .foregroundStyle(Color("WEInk"))

                    Text(
                        "Create a shared space, or enter the code your "
                        + "partner sent you."
                    )
                    .font(.weBody)
                    .foregroundStyle(Color("WEFaint"))

                    Button {
                        Task { await session.createCouple() }
                    } label: {
                        actionLabel("Create our space")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isWorking)

                    HStack(spacing: 10) {
                        TextField("JOIN CODE", text: $joinCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: joinCode) { _, value in
                                joinCode = String(
                                    value.uppercased().filter {
                                        $0.isLetter || $0.isNumber
                                    }.prefix(12)
                                )
                            }

                        Button("Join") {
                            Task {
                                await session.joinCouple(code: joinCode)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            session.isWorking
                                || joinCode.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        )
                    }

                    if let error = session.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Sign out") {
                        Task { await session.signOut() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color("WEFaint"))
                    .disabled(session.isWorking)
                }
                .frame(maxWidth: 520)
                .padding(28)
            }
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String) -> some View {
        if session.isWorking {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(
            AppSession(repository: PreviewRepository())
        )
}
