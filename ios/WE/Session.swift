import Foundation
import Supabase

@MainActor
final class Session: ObservableObject {
    enum Status { case loading, signedOut, needsCouple, ready }

    @Published var status: Status = .loading
    @Published var user: (id: String, name: String)?
    @Published var couple: (id: String, joinCode: String)?
    @Published var members: [Member] = []
    @Published var viewer: PersonID = ""
    @Published var records: [Record] = []
    @Published var reflections: [Reflection] = []
    @Published var busy = false
    @Published var errorText: String?
    @Published var info: String?

    let client = SupabaseClient(supabaseURL: Config.supabaseURL, supabaseKey: Config.supabaseAnonKey)

    var partner: Member? { members.first { $0.id != viewer } }
    func member(_ id: PersonID?) -> Member? { id.flatMap { mid in members.first { $0.id == mid } } }

    // MARK: - Auth

    func start() async {
        do {
            _ = try await client.auth.session
            await load()
        } catch {
            status = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        busy = true; errorText = nil; info = nil
        do {
            try await client.auth.signIn(email: email.trimmed, password: password)
            await load()
        } catch {
            errorText = friendly(error)
        }
        busy = false
    }

    func signUp(name: String, email: String, password: String) async {
        busy = true; errorText = nil; info = nil
        do {
            let res = try await client.auth.signUp(
                email: email.trimmed,
                password: password,
                data: ["name": .string(name.trimmed)]
            )
            if res.session == nil {
                info = "Check your email to confirm, then sign in."
            } else {
                await load()
            }
        } catch {
            errorText = friendly(error)
        }
        busy = false
    }

    func signOut() async {
        try? await client.auth.signOut()
        user = nil; couple = nil; members = []; records = []; reflections = []
        status = .signedOut
    }

    // MARK: - Pairing

    func createCouple() async {
        await run {
            let res: CoupleResult = try await self.client.rpc("create_couple").execute().value
            _ = res
            await self.load()
        }
    }

    func joinCouple(code: String) async {
        await run {
            _ = try await self.client.rpc("join_couple", params: JoinParam(p_code: code.trimmed)).execute()
            await self.load()
        }
    }

    // MARK: - Consent actions (server-enforced RPCs)

    func request(_ id: String) async { await rpc("request_reveal", InsightParam(p_insight: id)) }
    func accept(_ id: String) async { await rpc("accept_reveal", InsightParam(p_insight: id)) }
    func decline(_ id: String) async { await rpc("decline_reveal", InsightParam(p_insight: id)) }
    func withdraw(_ id: String) async { await rpc("withdraw_reveal", InsightParam(p_insight: id)) }
    func dismiss(_ id: String) async { await rpc("dismiss_suggestion", InsightParam(p_insight: id)) }

    func submit(_ id: String, choice: String, note: String?) async {
        await rpc("submit_response", SubmitParam(p_insight: id, p_choice: choice, p_note: note))
    }

    func settle(_ id: String, type: ResolutionType, choice: String?) async {
        await rpc("resolve_insight", ResolveParam(p_insight: id, p_type: type.rawValue, p_choice: choice))
    }

    private func rpc<P: Encodable>(_ fn: String, _ params: P) async {
        await run {
            _ = try await self.client.rpc(fn, params: params).execute()
            await self.load()
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        errorText = nil
        do { try await work() } catch { errorText = friendly(error) }
    }

    // MARK: - Load everything for the couple, then build projected records

    func load() async {
        do {
            let uid = try await client.auth.session.user.id.uuidString.lowercased()

            let profile: [ProfileRow] = try await client.from("profiles")
                .select("id,name").eq("id", value: uid).execute().value
            user = (uid, profile.first?.name ?? "You")
            viewer = uid

            let mine: [MembershipRow] = try await client.from("couple_members")
                .select("couple_id").eq("profile_id", value: uid).execute().value
            guard let coupleId = mine.first?.couple_id else {
                status = .needsCouple
                members = []; records = []; reflections = []
                return
            }

            async let coupleRows: [CoupleRow] = client.from("couples")
                .select("id,join_code").eq("id", value: coupleId).execute().value
            async let memberRows: [MemberRow] = client.from("couple_members")
                .select("profile_id,hue,profiles(name)").eq("couple_id", value: coupleId).execute().value
            async let insightRows: [InsightRow] = client.from("insights")
                .select("*").eq("couple_id", value: coupleId).order("sort").execute().value
            async let consentRows: [ConsentRow] = client.from("insight_consent").select("*").execute().value
            async let responseRows: [ResponseRow] = client.from("responses").select("*").execute().value
            async let dismissalRows: [DismissalRow] = client.from("dismissals").select("*").execute().value
            async let reflectionRows: [ReflectionRow] = client.from("reflections")
                .select("*").eq("owner_id", value: uid).execute().value

            let cRows = try await coupleRows
            let mRows = try await memberRows
            let iRows = try await insightRows
            let conRows = try await consentRows
            let rRows = try await responseRows
            let dRows = try await dismissalRows
            let reflRows = try await reflectionRows

            couple = cRows.first.map { ($0.id, $0.join_code) }
            members = mRows.map { Member(id: $0.profile_id, name: $0.profiles?.name ?? "Partner", hue: Hue(rawValue: $0.hue) ?? .burgundy) }
            let partnerID = members.first { $0.id != uid }?.id

            let consentByInsight = Dictionary(uniqueKeysWithValues: conRows.map { ($0.insight_id, $0) })
            var responsesByInsight: [String: [ResponseRow]] = [:]
            for r in rRows { responsesByInsight[r.insight_id, default: []].append(r) }
            let dismissed = Set(dRows.map { $0.insight_id })

            records = iRows.map { i in
                let c = consentByInsight[i.id]
                let rows = responsesByInsight[i.id] ?? []
                func resp(_ pid: String?) -> PersonResponse {
                    guard let pid, let row = rows.first(where: { $0.profile_id == pid }) else { return PersonResponse() }
                    return PersonResponse(status: ResponseStatus(rawValue: row.status) ?? .none, choice: row.choice, note: row.note)
                }
                var responses: [PersonID: PersonResponse] = [uid: resp(uid)]
                if let partnerID { responses[partnerID] = resp(partnerID) }

                let state = InsightState(
                    visibility: c.flatMap { Visibility(rawValue: $0.visibility) } ?? .shared,
                    owner: c?.owner_id,
                    readiness: c.flatMap { Readiness(rawValue: $0.readiness) } ?? .idle,
                    initiator: c?.initiator_id,
                    requestedAt: c?.requested_at.flatMap(parseTimestamp),
                    acceptedAt: c?.accepted_at.flatMap(parseTimestamp),
                    responses: responses,
                    dismissedBy: dismissed.contains(i.id) ? [uid] : [],
                    resolution: c?.resolution_type.flatMap { ResolutionType(rawValue: $0) }.map { Resolution(type: $0, choice: c?.resolution_choice) }
                )
                let insight = Insight(id: i.id, kind: InsightKind(rawValue: i.kind) ?? .logistical,
                                      domain: Domain(rawValue: i.domain) ?? .life, present: i.present,
                                      title: i.title, body: i.body, evidence: i.evidence, source: i.source, options: i.options)
                return Record(insight: insight, state: state)
            }

            reflections = reflRows.map {
                Reflection(id: $0.id, owner: $0.owner_id, domain: Domain(rawValue: $0.domain) ?? .life,
                           kind: ReflectionKind(rawValue: $0.kind) ?? .reflection, text: $0.text)
            }

            status = .ready
        } catch {
            errorText = friendly(error)
            if case .loading = status { status = .signedOut }
        }
    }
}

// MARK: - RPC params

private struct InsightParam: Encodable { let p_insight: String }
private struct JoinParam: Encodable { let p_code: String }
private struct SubmitParam: Encodable { let p_insight: String; let p_choice: String; let p_note: String? }
private struct ResolveParam: Encodable { let p_insight: String; let p_type: String; let p_choice: String? }
private struct CoupleResult: Decodable { let couple_id: String; let join_code: String }

// MARK: - DB rows (snake_case, decoded directly from PostgREST)

private struct ProfileRow: Decodable { let id: String; let name: String }
private struct MembershipRow: Decodable { let couple_id: String }
private struct CoupleRow: Decodable { let id: String; let join_code: String }
private struct NameOnly: Decodable { let name: String }
private struct MemberRow: Decodable { let profile_id: String; let hue: String; let profiles: NameOnly? }
private struct InsightRow: Decodable {
    let id: String; let kind: String; let domain: String; let present: Bool
    let title: String; let body: String; let evidence: String; let source: String; let options: [String]
}
private struct ConsentRow: Decodable {
    let insight_id: String; let visibility: String; let owner_id: String?
    let readiness: String; let initiator_id: String?
    let requested_at: String?; let accepted_at: String?
    let resolution_type: String?; let resolution_choice: String?; let resolved_at: String?
}
private struct ResponseRow: Decodable { let insight_id: String; let profile_id: String; let status: String; let choice: String?; let note: String? }
private struct DismissalRow: Decodable { let insight_id: String; let profile_id: String }
private struct ReflectionRow: Decodable { let id: String; let owner_id: String; let domain: String; let kind: String; let text: String }

// MARK: - Helpers

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private func parseTimestamp(_ s: String) -> Date? {
    isoFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}

private func friendly(_ error: Error) -> String {
    let msg = (error as NSError).localizedDescription
    return msg.isEmpty ? "Something went wrong." : msg
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
