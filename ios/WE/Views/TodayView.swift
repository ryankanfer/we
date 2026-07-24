import SwiftUI
import UIKit

struct TodayView: View {
    @EnvironmentObject var session: Session

    private var active: [(Record, Projection)] {
        session.records.compactMap { r in
            guard let p = Consent.project(r.state, viewer: session.viewer), !p.dismissed, p.phase != .resolved else { return nil }
            return (r, p)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if session.members.count < 2 { InviteBanner() }

                    section("Today together") {
                        HStack(alignment: .top, spacing: 12) {
                            glanceCard
                            energyCard
                        }
                    }

                    dateNightCard

                    section("What needs us") {
                        if active.isEmpty {
                            allQuiet
                        } else {
                            VStack(spacing: 12) {
                                ForEach(active, id: \.0.id) { (r, p) in
                                    NavigationLink(value: r.id) { InsightCardView(insight: r.insight, projection: p) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    section("Tiny moment") { tinyMoment }
                }
                .padding(20)
            }
            .background(Palette.cream)
            .navigationDestination(for: String.self) { id in InsightDetailView(insightID: id) }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Good evening, \(session.user?.name ?? "")." ).font(.serif(32))
                Text(session.partner.map { "You and \($0.name), today." } ?? "Here’s what needs the two of you.")
                    .font(.system(size: 14)).foregroundColor(Palette.faint)
            }
            Spacer()
            Image(systemName: "person.2")
                .foregroundColor(Palette.faint)
                .frame(width: 36, height: 36).overlay(Circle().stroke(Palette.line, lineWidth: 1))
        }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: label)
            content()
        }
    }

    private var glanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AT A GLANCE").font(.system(size: 11, weight: .medium)).tracking(1.4).foregroundColor(Palette.cream.opacity(0.6))
            glanceRow("calendar", "2 events today")
            glanceRow("checkmark", "1 task together")
            glanceRow("fork.knife", "Dinner at 7:00")
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ink).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func glanceRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(Palette.cream.opacity(0.7)).frame(width: 16)
            Text(text).font(.system(size: 15)).foregroundColor(Palette.cream)
        }
    }

    private var energyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ENERGY CHECK-IN").font(.system(size: 11, weight: .medium)).tracking(1.4).foregroundColor(Palette.faint)
            ForEach(Array(session.members.enumerated()), id: \.element.id) { (i, m) in
                HStack {
                    HStack(spacing: 8) { Dot(hue: m.hue); Text(m.id == session.viewer ? "You" : m.name).font(.system(size: 15)) }
                    Spacer()
                    Text(i == 0 ? "Steady" : "Stretched").font(.system(size: 15)).foregroundColor(Palette.faint)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).weCard()
    }

    private var dateNightCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TOMORROW").font(.system(size: 11, weight: .medium)).tracking(1.4).foregroundColor(Palette.cream.opacity(0.6))
                Text("Date night").font(.serif(24)).foregroundColor(Palette.cream)
                Text("7:00 PM · Nami").font(.system(size: 14)).foregroundColor(Palette.cream.opacity(0.75))
            }
            Spacer()
            Image(systemName: "fork.knife").font(.system(size: 26)).foregroundColor(Palette.cream.opacity(0.7))
        }
        .padding(22).background(Palette.burgundy).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var allQuiet: some View {
        VStack(spacing: 8) {
            InterlockMark(overlap: .interlocked, size: 44)
            Text("All quiet.").font(.serif(18)).padding(.top, 4)
            Text("WE stays still unless something is worth the two of you.")
                .font(.system(size: 14)).foregroundColor(Palette.faint).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32).weCard()
    }

    private var tinyMoment: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart").foregroundColor(Palette.burgundy)
                .frame(width: 40, height: 40).background(Palette.burgundySoft).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Thinking of you").font(.system(size: 15))
                Text("Send a small moment to \(session.partner?.name ?? "your partner")").font(.system(size: 14)).foregroundColor(Palette.faint)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14)).foregroundColor(Palette.faint)
        }
        .padding(16).weCard()
    }
}

struct InviteBanner: View {
    @EnvironmentObject var session: Session
    var body: some View {
        if let couple = session.couple {
            VStack(alignment: .leading, spacing: 12) {
                Text("It’s just you here so far. Share this code with your partner so they can join your space.")
                    .font(.system(size: 14))
                HStack(spacing: 8) {
                    Text(couple.joinCode).font(.serif(18)).tracking(6).foregroundColor(Palette.cream)
                    Text("tap to copy").font(.system(size: 12)).foregroundColor(Palette.cream.opacity(0.8))
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Palette.ink).clipShape(Capsule())
                .onTapGesture { UIPasteboard.general.string = couple.joinCode }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.sageSoft).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct InsightCardView: View {
    @EnvironmentObject var session: Session
    let insight: Insight
    let projection: Projection

    private var kindLabel: String {
        switch insight.kind { case .logistical: return "Logistics"; case .relational: return "Time together"; case .unresolved: return "Still open" }
    }

    private var mark: Overlap {
        switch projection.phase {
        case .revealed, .resolved, .answering, .held: return .interlocked
        case .waiting, .invited: return .touching
        default: return .apart
        }
    }

    private var status: String? {
        let partner = session.partner?.name ?? "your partner"
        switch projection.phase {
        case .waiting: return "Waiting for \(partner) to open this with you"
        case .invited: return "\(session.member(projection.initiator)?.name ?? "Someone") brought this to you"
        case .answering: return "Open between you — your answer is still yours"
        case .held: return "Your answer is in. Waiting for \(partner)’s"
        case .revealed: return (projection.matched == true) ? "You’re in the same place" : "Not in the same place yet"
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: kindLabel)
                Spacer()
                InterlockMark(overlap: mark, size: 22, breathing: projection.phase == .waiting)
            }
            Text(insight.title).font(.serif(22)).foregroundColor(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let status { Text(status).font(.system(size: 14)).foregroundColor(Palette.faint) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).weCard()
    }
}
