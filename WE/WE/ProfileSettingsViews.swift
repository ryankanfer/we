import SwiftUI

//
//  Two settings screens reached from Profile — "How WE notices" and
//  "Mode". They were the only live views left in `V2ExperienceViews` when
//  the zones replaced it, so they were lifted out and the rest deleted.
//

struct SignalConsentView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        List {
            Section {
                Text("WE notices only shared signals both people allow. Private reflection is outside the intelligence layer.")
            }

            ForEach(SignalKind.allCases, id: \.self) { signal in
                Toggle(
                    isOn: Binding(
                        get: { enabled(signal) },
                        set: { value in
                            Task {
                                await session.setSignalConsent(
                                    signal,
                                    enabled: value
                                )
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(signal.title)
                        Text(signal.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(
                    signal.isPermanentlyDisabled || !session.canMutate
                )
                .accessibilityHint(signal.detail)
            }
        }
        .navigationTitle("How WE notices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func enabled(_ signal: SignalKind) -> Bool {
        guard !signal.isPermanentlyDisabled else { return false }
        return session.v2State.signalConsents.first {
            $0.profileID == session.user?.id && $0.signal == signal
        }?.isEnabled ?? true
    }
}

struct ModeSettingsView: View {
    @EnvironmentObject private var host: SessionHost
    @State private var confirmsReset = false

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: modeBinding) {
                    ForEach(AppMode.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(
                    host.mode == .actual
                        ? "Actual uses your live relationship and Supabase."
                        : "Simulation is local to this device and never writes to Supabase."
                )
            }

            if host.mode == .simulation {
                Section("Viewer") {
                    Picker("Viewing as", selection: viewerBinding) {
                        ForEach(SimulationViewer.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Reset scenario", role: .destructive) {
                        confirmsReset = true
                    }
                }
            }
        }
        .navigationTitle("Mode")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset the shared simulation?",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Reset simulation", role: .destructive) {
                Task { await host.resetSimulation() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ryan and Dylan will both return to the starting scenario.")
        }
    }

    private var modeBinding: Binding<AppMode> {
        Binding(
            get: { host.mode },
            set: { value in Task { await host.setMode(value) } }
        )
    }

    private var viewerBinding: Binding<SimulationViewer> {
        Binding(
            get: { host.viewer },
            set: { value in Task { await host.setViewer(value) } }
        )
    }
}
