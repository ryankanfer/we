import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class ShareExtensionModel {
    enum State {
        case loading
        case ready(IncomingShareDraft)
        case saving(IncomingShareDraft)
        case kept(IncomingShareManifest)
        case failure(String, [IncomingShareOmission])
    }

    private(set) var state: State = .loading
    private(set) var hueToken = "burgundy"

    private weak var extensionContext: NSExtensionContext?
    private var vaultContext: ShareVaultContext?

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    func load() async {
        guard case .loading = state else { return }
        guard let extensionContext else {
            state = .failure("WE could not read what was shared.", [])
            return
        }
        do {
            let context = try ShareVaultController.shared.activeContext()
            vaultContext = context
            hueToken = context.pointer.hueToken
            ShareVaultController.shared.store.cleanAbandonedStaging(
                context: context,
                olderThan: Date().addingTimeInterval(-86_400)
            )
            let candidates = await ShareExtensionLoader.candidates(
                from: extensionContext
            )
            let draft = try IncomingShareParser.parse(
                candidates,
                vaultID: context.pointer.vaultID
            )
            state = .ready(draft)
            announce(
                "\(draft.manifest.summary) ready. Private until you review."
            )
        } catch let rejection as IncomingShareRejection {
            // Nothing was kept, but the person still gets told what each item
            // was and why it did not qualify.
            state = .failure(rejection.localizedDescription, rejection.omissions)
            announce(
                rejection.omissions.isEmpty
                    ? rejection.localizedDescription
                    : "\(rejection.localizedDescription) \(rejection.omissions.count) items left out."
            )
        } catch {
            state = .failure(error.localizedDescription, [])
            announce(error.localizedDescription)
        }
    }

    func keep() {
        guard case .ready(let draft) = state,
              let vaultContext else { return }
        state = .saving(draft)
        do {
            try ShareVaultController.shared.store.commit(
                draft,
                context: vaultContext
            )
            state = .kept(draft.manifest)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            announce("Kept on your side.")
            Task {
                // The ring settles over 320ms. Dismissing at 250ms cut it off
                // and gave "Kept on your side." no time to be read.
                try? await Task.sleep(for: .milliseconds(900))
                extensionContext?.completeRequest(returningItems: nil)
            }
        } catch {
            state = .failure(
                "WE couldn't keep this private draft. Nothing was saved.",
                []
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            announce("Nothing was saved.")
        }
    }

    func cancel() {
        extensionContext?.cancelRequest(
            withError: CocoaError(.userCancelled)
        )
    }

    private func announce(_ message: String) {
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }
}

struct WEShareExtensionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Bindable var model: ShareExtensionModel
    @State private var drifted = false

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.047, blue: 0.044)
                .ignoresSafeArea()

            ambientField
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    content
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 34)
                        .padding(.bottom, 30)
                }

                actionBar
            }
        }
        .preferredColorScheme(.dark)
        .task { await model.load() }
        .task(id: isReady) {
            guard isReady, !reduceMotion else { return }
            // Drift immediately and continuously. Sleeping first left the
            // field motionless for the first eight seconds — the exact window
            // the person is actually looking at it.
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 9)) {
                    drifted.toggle()
                }
                try? await Task.sleep(for: .seconds(9))
            }
        }
    }

    private var header: some View {
        HStack {
            Text("WE")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(.white.opacity(0.82))

            Spacer(minLength: 12)

            Button("Close") { model.cancel() }
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityIdentifier("share.close")
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
        .background(
            reduceTransparency
                ? Color(red: 0.055, green: 0.047, blue: 0.044)
                : Color(red: 0.055, green: 0.047, blue: 0.044).opacity(0.96)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            stateMark
            ProgressView()
                .tint(.white.opacity(0.75))
                .padding(.top, 26)
                .accessibilityLabel("Reading the shared item")

        case .ready(let draft):
            stateMark
            Text("Ready to keep")
                .font(.system(.title2, design: .serif, weight: .regular))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.top, 24)
            Text("Private until you review.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.64))
                .padding(.top, 8)
            summary(draft.manifest)

        case .saving(let draft):
            stateMark
            Text("Keeping \(draft.manifest.summary)…")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 24)

        case .kept:
            stateMark
            Text("Kept on your side.")
                .font(.system(.title2, design: .serif, weight: .regular))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.top, 24)

        case .failure(let message, let omissions):
            stateMark
            Text("Not kept")
                .font(.system(.title2, design: .serif, weight: .regular))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.top, 24)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)

            if !omissions.isEmpty {
                VStack(alignment: .leading, spacing: 15) {
                    Divider().overlay(.white.opacity(0.14))
                    Text("LEFT OUT")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.48))

                    ForEach(omissions) { omission in
                        Text("\(omission.label): \(omission.reason)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func summary(_ manifest: IncomingShareManifest) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(manifest.summary.uppercased())
                .font(.caption.weight(.medium))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.55))

            Text(manifest.titleSuggestion)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(.white.opacity(0.14))
            Text("KEPT PRIVATELY")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.48))

            ForEach(manifest.representations) { representation in
                acceptedRepresentation(
                    representation,
                    resources: manifest.resources
                )
            }

            if !manifest.omissions.isEmpty {
                Divider().overlay(.white.opacity(0.14))
                Text("LEFT OUT")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.48))

                ForEach(manifest.omissions) { omission in
                    Text("\(omission.label): \(omission.reason)")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Deliberately `.contain`, not `.combine`. This list is the whole
        // promise of the screen — what is kept and what was dropped. Combining
        // it flattens every line into one unnavigable utterance.
        .accessibilityElement(children: .contain)
    }

    private func acceptedRepresentation(
        _ representation: IncomingShareRepresentation,
        resources: [IncomingShareResource]
    ) -> some View {
        let value: String
        switch representation.kind {
        case .text:
            value = representation.text ?? "Text"
        case .url:
            value = representation.url?.absoluteString ?? "Secure link"
        case .image:
            if let resource = resources.first(
                where: { $0.id == representation.resourceID }
            ),
            let width = resource.pixelWidth,
            let height = resource.pixelHeight {
                value = "Photo · \(width) × \(height)"
            } else {
                value = "Photo"
            }
        }

        // Shared text runs to 20,000 characters. The confirmation is a glance,
        // not the document — the full text stays readable in the app's review.
        return Text(value)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.74))
            .lineLimit(6)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stateMark: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 1)
                .frame(width: 74, height: 74)

            Circle()
                .trim(from: 0, to: isKept ? 1 : 0.08)
                .stroke(
                    personalHue.opacity(0.9),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 74, height: 74)
                .animation(
                    reduceMotion ? nil : .timingCurve(
                        0.16, 1, 0.3, 1,
                        duration: 0.32
                    ),
                    value: isKept
                )

            Text("WE")
                .font(.system(.headline, design: .rounded, weight: .medium))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var actionBar: some View {
        switch model.state {
        case .ready:
            Button("Keep in WE") { model.keep() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(red: 0.07, green: 0.055, blue: 0.05))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .accessibilityHint("Keeps a private draft. Nothing is shared with your partner.")
                .accessibilityIdentifier("share.keep")
        case .saving:
            ProgressView()
                .tint(.white)
                .frame(minHeight: 76)
                .accessibilityLabel("Keeping the private draft")
        case .failure:
            // A dead end needs a way out that is not a 44pt word in the
            // corner.
            Button("Close") { model.cancel() }
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .accessibilityIdentifier("share.failure.close")
        default:
            Color.clear.frame(height: 20)
        }
    }

    private var ambientField: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: meshPoints,
            colors: meshColors
        )
        .opacity(isKept ? 0.12 : 0.72)
        .scaleEffect(isKept && !reduceMotion ? 0.28 : 1.04)
        .animation(
            reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.32),
            value: isKept
        )
    }

    private var meshPoints: [SIMD2<Float>] {
        [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5],
            drifted ? [0.53, 0.47] : [0.49, 0.51],
            [1, 0.5],
            [0, 1],
            drifted ? [0.47, 1] : [0.51, 0.98],
            [1, 1],
        ]
    }

    private var meshColors: [Color] {
        let quiet = Color(red: 0.055, green: 0.047, blue: 0.044)
        return [
            quiet, quiet, quiet,
            quiet, personalHue.opacity(0.24), quiet,
            quiet, personalHue.opacity(0.18), quiet,
        ]
    }

    private var personalHue: Color {
        switch model.hueToken {
        case "sage": Color(red: 0.48, green: 0.62, blue: 0.49)
        case "ember": Color(red: 0.77, green: 0.38, blue: 0.25)
        case "tide": Color(red: 0.31, green: 0.55, blue: 0.62)
        case "plum": Color(red: 0.47, green: 0.29, blue: 0.45)
        case "clay": Color(red: 0.65, green: 0.43, blue: 0.34)
        case "pearl": Color(red: 0.81, green: 0.76, blue: 0.7)
        case "mist": Color(red: 0.56, green: 0.62, blue: 0.65)
        case "blush": Color(red: 0.73, green: 0.49, blue: 0.5)
        case "celadon": Color(red: 0.58, green: 0.68, blue: 0.58)
        default: Color(red: 0.55, green: 0.19, blue: 0.25)
        }
    }

    private var isReady: Bool {
        if case .ready = model.state { return true }
        return false
    }

    private var isKept: Bool {
        if case .kept = model.state { return true }
        return false
    }
}
