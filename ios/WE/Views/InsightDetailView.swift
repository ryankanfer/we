import SwiftUI

struct InsightDetailView: View {
    @EnvironmentObject var session: Session
    let insightID: String

    private var record: Record? { session.records.first { $0.id == insightID } }

    var body: some View {
        ScrollView {
            if let record, let p = Consent.project(record.state, viewer: session.viewer) {
                content(record.insight, p)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 16) {
                    InterlockMark(overlap: .apart, size: 48)
                    Text("This isn’t here anymore.").font(.serif(20))
                }
                .frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .background(Palette.cream)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ insight: Insight, _ p: Projection) -> some View {
        switch p.phase {
        case .open: OpenPhase(insight: insight)
        case .waiting: WaitingPhase(insight: insight, projection: p)
        case .invited: InvitedPhase(insight: insight, projection: p)
        case .answering, .held: AnsweringPhase(insight: insight, projection: p)
        case .revealed: RevealedPhase(insight: insight, projection: p)
        case .resolved: ResolvedPhase(insight: insight, projection: p)
        }
    }
}

// MARK: - Shared pieces

private struct Observation: View {
    let insight: Insight
    var muted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(insight.title).font(.serif(27)).fixedSize(horizontal: false, vertical: true)
            Text(insight.body).font(.system(size: 15)).foregroundColor(Palette.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(muted ? 0.8 : 1)
    }
}

private struct Evidence: View {
    let insight: Insight
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Why WE noticed this")
            Text(insight.evidence).font(.system(size: 14))
            Text(insight.source).font(.system(size: 12)).foregroundColor(Palette.faint)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AnswerCard: View {
    @EnvironmentObject var session: Session
    let member: Member?
    let choice: String?
    let note: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PersonChip(member: member, suffix: "chose")
            Text(choice ?? "—").font(.serif(18))
            if let note { Text("“\(note)”").font(.system(size: 14)).foregroundColor(Palette.ink.opacity(0.75)) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background((member?.hue ?? .burgundy).soft)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Phases

private struct OpenPhase: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) var dismiss
    let insight: Insight
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Observation(insight: insight)
            Evidence(insight: insight)
            VStack(spacing: 4) {
                PrimaryButton(title: "Bring this to us") { Task { await session.request(insight.id) } }
                Text("Your partner will see the topic and that it came from you — nothing more.")
                    .font(.system(size: 12)).foregroundColor(Palette.faint).multilineTextAlignment(.center)
                    .padding(.top, 8)
                QuietButton(title: "Not now") { dismiss() }
                QuietButton(title: "Dismiss this suggestion — just for you") {
                    Task { await session.dismiss(insight.id); dismiss() }
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct WaitingPhase: View {
    @EnvironmentObject var session: Session
    let insight: Insight
    let projection: Projection
    private var later: Bool {
        guard let at = projection.requestedAt else { return false }
        return Date().timeIntervalSince(at) >= 18 * 3600
    }
    var body: some View {
        VStack(spacing: 0) {
            InterlockMark(overlap: .touching, size: 72, breathing: true).padding(.top, 40)
            Text(later ? "Still with \(session.partner?.name ?? "your partner")."
                       : "Waiting for \(session.partner?.name ?? "your partner") to open this with you.")
                .font(.serif(23)).multilineTextAlignment(.center).padding(.top, 32)
            Text(later ? "This stays quietly open. WE won’t ask again, and no one is keeping count."
                       : "They’ll come to it in their own time. WE won’t nudge.")
                .font(.system(size: 14)).foregroundColor(Palette.faint).multilineTextAlignment(.center).padding(.top, 12)
            Text("“\(insight.title)”").font(.serif(16)).foregroundColor(Palette.ink.opacity(0.7))
                .multilineTextAlignment(.center).padding(.top, 24)
            QuietButton(title: "Take it back — no record will remain") { Task { await session.withdraw(insight.id) } }
                .padding(.top, 40)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct InvitedPhase: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) var dismiss
    let insight: Insight
    let projection: Projection
    var body: some View {
        VStack(spacing: 0) {
            InterlockMark(overlap: .touching, size: 56).padding(.top, 24)
            PersonChip(member: session.member(projection.initiator), suffix: "brought something to you").padding(.top, 24)
            Text(insight.title).font(.serif(26)).multilineTextAlignment(.center).padding(.top, 12)
            Text("Opening it means you’re ready to sit with this together. You’ll each answer privately first.")
                .font(.system(size: 14)).foregroundColor(Palette.faint).multilineTextAlignment(.center).padding(.top, 16)
            VStack(spacing: 4) {
                PrimaryButton(title: "Open this together") { Task { await session.accept(insight.id) } }
                QuietButton(title: "Not yet — \(session.member(projection.initiator)?.name ?? "they") won’t be told") {
                    Task { await session.decline(insight.id); dismiss() }
                }
            }
            .padding(.top, 40)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AnsweringPhase: View {
    @EnvironmentObject var session: Session
    let insight: Insight
    let projection: Projection
    @State private var choice: String?
    @State private var note: String = ""

    var body: some View {
        if projection.phase == .held {
            VStack(spacing: 0) {
                InterlockMark(overlap: .interlocked, size: 72, breathing: true).padding(.top, 40)
                Text("Your answer is in.").font(.serif(23)).padding(.top, 32)
                Text("It stays yours until \(session.partner?.name ?? "your partner") has answered too. Then you’ll see both, together.")
                    .font(.system(size: 14)).foregroundColor(Palette.faint).multilineTextAlignment(.center).padding(.top, 12)
                Text("“\(insight.title)”").font(.serif(16)).foregroundColor(Palette.ink.opacity(0.7))
                    .multilineTextAlignment(.center).padding(.top, 24)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                Observation(insight: insight, muted: true)
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Your answer — private until you’ve both answered")
                    ForEach(insight.options, id: \.self) { opt in
                        Button { choice = opt } label: {
                            HStack {
                                Image(systemName: choice == opt ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(choice == opt ? Palette.ink : Palette.faint)
                                Text(opt).font(.system(size: 15)).foregroundColor(Palette.ink)
                                Spacer()
                            }
                            .padding(14)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(choice == opt ? Palette.ink : Palette.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "A private note, if you want one")
                    TextField("Only revealed alongside theirs.", text: $note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true).font(.system(size: 15))
                        .padding(12).weCard()
                }
                PrimaryButton(title: choice == nil ? "Choose an answer first" : "Share when you’re both ready",
                              enabled: choice != nil) {
                    if let choice { Task { await session.submit(insight.id, choice: choice, note: note.isEmpty ? nil : note) } }
                }
            }
            .onAppear { choice = projection.myResponse.choice; note = projection.myResponse.note ?? "" }
        }
    }
}

private struct RevealedPhase: View {
    @EnvironmentObject var session: Session
    let insight: Insight
    let projection: Projection
    @State private var showDetail = false
    private var matched: Bool { projection.matched == true }

    var body: some View {
        VStack(spacing: 0) {
            InterlockMark(overlap: matched ? .interlocked : .touching, size: 56).padding(.top, 16)
            Text(matched ? "You’re in the same place." : "You’re not in the same place yet.")
                .font(.serif(26)).multilineTextAlignment(.center).padding(.top, 20)
            if !matched { Text("Nothing has been decided.").font(.system(size: 14)).foregroundColor(Palette.faint).padding(.top, 8) }

            if matched || showDetail {
                VStack(spacing: 12) {
                    AnswerCard(member: session.member(session.viewer), choice: projection.myResponse.choice, note: projection.myResponse.note)
                    AnswerCard(member: session.partner, choice: projection.partnerResponse?.choice, note: projection.partnerResponse?.note)
                }
                .padding(.top, 24)
            }

            VStack(spacing: 4) {
                if matched {
                    let release = projection.myResponse.choice == "Let this go together"
                    PrimaryButton(title: release ? "Let it go, together" : "Mark it settled") {
                        Task { await session.settle(insight.id, type: release ? .released : .settled, choice: projection.myResponse.choice) }
                    }
                } else {
                    if !showDetail {
                        PrimaryButton(title: "See what matters to each of you") { showDetail = true }
                    }
                    QuietButton(title: "Leave this open — it can wait") {
                        Task { await session.settle(insight.id, type: .leftOpen, choice: nil) }
                    }
                }
            }
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ResolvedPhase: View {
    @EnvironmentObject var session: Session
    let insight: Insight
    let projection: Projection
    private var label: String {
        switch projection.resolution?.type {
        case .released: return "Let go, together."
        case .leftOpen: return "Left open, together."
        default: return "Settled, together."
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            InterlockMark(overlap: .interlocked, size: 56).padding(.top, 24)
            Text(label).font(.serif(24)).padding(.top, 24)
            Text("“\(insight.title)”").font(.serif(16)).foregroundColor(Palette.ink.opacity(0.7))
                .multilineTextAlignment(.center).padding(.top, 12)
            VStack(spacing: 12) {
                AnswerCard(member: session.member(session.viewer), choice: projection.myResponse.choice, note: projection.myResponse.note)
                AnswerCard(member: session.partner, choice: projection.partnerResponse?.choice, note: projection.partnerResponse?.note)
            }
            .padding(.top, 24).opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}
