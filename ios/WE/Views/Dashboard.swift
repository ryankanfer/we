import SwiftUI

struct PlanView: View {
    private let days: [(String, Int)] = [("M",20),("T",21),("W",22),("T",23),("F",24),("S",25),("S",26)]
    private let events: [(String, String, Bool)] = [
        ("8 AM","Ry — Workout", false), ("10 AM","Team standup", false),
        ("12 PM","Alex — Client call", false), ("2 PM","Grocery run", false),
        ("6 PM","Dinner at Nami · Date night", true), ("9 PM","Wind down", false),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("This week").font(.serif(32))
                HStack(spacing: 4) {
                    ForEach(days, id: \.1) { d in
                        VStack(spacing: 8) {
                            Text(d.0).font(.system(size: 11, weight: .medium)).foregroundColor(Palette.faint)
                            Text("\(d.1)").font(.system(size: 15))
                                .frame(width: 36, height: 36)
                                .background(d.1 == 22 ? Palette.ink : Color.clear)
                                .foregroundColor(d.1 == 22 ? Palette.cream : Palette.ink)
                                .clipShape(Circle())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(events, id: \.0) { e in
                        HStack(spacing: 14) {
                            Text(e.0).font(.system(size: 12)).foregroundColor(Palette.faint).frame(width: 48, alignment: .trailing)
                            Text(e.1).font(.system(size: 15)).foregroundColor(e.2 ? Palette.cream : Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(e.2 ? Palette.burgundy : Palette.card)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(e.2 ? Color.clear : Palette.line, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.cream)
    }
}

struct HomeView: View {
    @State private var tab = 0
    private let tabs = ["Mental load", "Home", "Finances"]
    private let upNext: [(String, String)] = [
        ("Buy birthday gift for Mom","R"), ("Call the landlord","A"),
        ("Renew passports","•"), ("Book vet appointment","A"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Home").font(.serif(32))
                Picker("", selection: $tab) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { i, t in Text(t).tag(i) }
                }
                .pickerStyle(.segmented)

                SectionLabel(text: "Up next")
                VStack(spacing: 0) {
                    ForEach(Array(upNext.enumerated()), id: \.offset) { i, item in
                        HStack {
                            Image(systemName: "circle").foregroundColor(Palette.faint).font(.system(size: 15))
                            Text(item.0).font(.system(size: 15))
                            Spacer()
                            Text(item.1).font(.system(size: 12, weight: .medium)).foregroundColor(Palette.faint)
                                .frame(width: 26, height: 26).background(Palette.burgundySoft).clipShape(Circle())
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        if i < upNext.count - 1 { Divider().background(Palette.line) }
                    }
                }
                .weCard()

                SectionLabel(text: "Going smoothly")
                HStack(spacing: 10) {
                    smoothly("basket", "Groceries", "On track")
                    smoothly("doc.text", "Bills", "Paid")
                    smoothly("leaf", "Plants", "Watered")
                }
            }
            .padding(20)
        }
        .background(Palette.cream)
    }

    private func smoothly(_ icon: String, _ label: String, _ sub: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(Palette.sage)
            Text(label).font(.system(size: 13, weight: .medium))
            Text(sub).font(.system(size: 12)).foregroundColor(Palette.faint)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(Palette.sageSoft).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ProfileView: View {
    @EnvironmentObject var session: Session
    private let promise = [
        "Some things stay yours until you both choose to open them — together.",
        "“Not now” is always safe. No one is told, and no one keeps count.",
        "WE describes patterns. It never diagnoses people, and it never scores you.",
        "The better things are, the quieter WE becomes.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Profile").font(.serif(32))

                HStack(spacing: 16) {
                    Avatar(member: session.member(session.viewer), size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.user?.name ?? "").font(.serif(20))
                        Text(session.partner.map { "Paired with \($0.name)" } ?? "Waiting for your partner to join")
                            .font(.system(size: 14)).foregroundColor(Palette.faint)
                    }
                    Spacer()
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).weCard()

                if let couple = session.couple, session.members.count < 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Your shared space")
                        Text("Invite code: \(couple.joinCode)").font(.system(size: 15))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "The promise")
                    ForEach(promise, id: \.self) { line in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(Palette.ink.opacity(0.4)).frame(width: 4, height: 4).padding(.top, 8)
                            Text(line).font(.serif(16)).foregroundColor(Palette.ink.opacity(0.85))
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).weCard()

                Button("Sign out") { Task { await session.signOut() } }
                    .font(.system(size: 14)).foregroundColor(Palette.faint)
            }
            .padding(20)
        }
        .background(Palette.cream)
    }
}
