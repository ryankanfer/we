//
//  FieldTargetPhrasing.swift
//  WE
//
//  Who or what a sentence is about.
//
//  A sibling to `FieldPhrasing`, and the same discipline: nothing is invented
//  and nothing is inferred. It takes the words that are already there, drops
//  the ones that are scaffolding — the verb, the day, the articles — and
//  returns what is left. A phrase that does not name anybody returns nil, and
//  the app says so rather than guessing.
//
//  It also decides whether the thing is a person or a place, and that decision
//  is deliberately lopsided. A wrong place is a wrong address on a screen
//  somebody reads before tapping. A wrong person is somebody's real phone
//  number. So a name only counts as a person when the sentence gives a real
//  reason to think so, and everything else is looked for as a business.
//

import Foundation

enum FieldTargetPhrasing {
    struct Extraction: Hashable, Sendable {
        var target: String
        var kind: FieldTargetQuery.Kind

        var query: FieldTargetQuery {
            FieldTargetQuery(text: target, kind: kind)
        }
    }

    /// The verbs each act is normally phrased with. Stripped from anywhere in
    /// the sentence, because "the vet needs booking" and "book the vet" are
    /// the same errand written two ways.
    private static let actVerbs: [FieldAct: [String]] = [
        .call: ["call", "ring", "phone", "give a call", "call up"],
        .message: ["text", "message", "rsvp to", "rsvp", "reply to", "forward to"],
        .email: ["email", "mail", "write to"],
        .book: ["book", "booking", "reserve", "reservation for", "reservation",
                "make an appointment with", "appointment with", "appointment",
                "get an appointment at"],
        .schedule: ["schedule", "reschedule", "set up", "arrange"],
    ]

    /// Words that are never the subject: articles, glue, and the possessives
    /// that attach a thing to a person without naming either.
    private static let filler: Set<String> = [
        "a", "an", "the", "my", "our", "your", "his", "her", "their", "its",
        "to", "for", "with", "at", "in", "on", "about", "and", "or", "some",
        "that", "this", "it", "them", "please", "need", "needs", "needed",
        "want", "wants", "get", "got", "make", "made", "do", "does", "done",
        "up", "out", "back", "again", "another", "new", "next",
    ]

    /// Words that mean a person even when no name is given. Kinship only —
    /// the app knows what "mom" means to a couple and has no business
    /// guessing that "sam" is one.
    private static let kinship: Set<String> = [
        "mom", "mum", "mother", "dad", "father", "grandma", "grandmother",
        "gran", "nana", "grandpa", "grandfather", "papa", "sister", "brother",
        "aunt", "uncle", "cousin",
    ]

    /// Trades a couple calls, and the reason "place" is the safe default: a
    /// vet is a business with a listing, and looking one up costs nobody
    /// anything.
    private static let trades: Set<String> = [
        "vet", "dentist", "doctor", "dr", "gp", "clinic", "pharmacy",
        "salon", "barber", "garage", "mechanic", "restaurant", "hotel",
        "plumber", "electrician", "landlord", "super", "school", "gym",
        "hospital", "pediatrician", "groomer",
    ]

    static func extract(
        from title: String,
        act: FieldAct,
        identity: FieldIdentity
    ) -> Extraction? {
        var words = title
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
            .map(String.init)

        // The act's own verb, then every day word, then the filler. Order
        // matters only in that the day list is shared with `FieldPhrasing` —
        // "call the vet friday" is about the vet.
        let verbs = actVerbs[act] ?? []
        words.removeAll { word in
            verbs.contains(where: { $0.split(separator: " ").contains(word[...]) })
                || FieldPhrasing.dayPhrases.contains(word)
                || filler.contains(word)
        }

        guard let first = words.first else { return nil }

        // A partner's own name is a person, and so is anything the couple
        // would call a relative. Everything else is looked for as a business.
        let namesAPartner = [identity.nameA, identity.nameB].contains {
            $0.compare(first, options: .caseInsensitive) == .orderedSame
        }
        let kind: FieldTargetQuery.Kind =
            namesAPartner || kinship.contains(first) ? .person : .place

        // A place reads better with the word beside it — "hudson vet" beats
        // "hudson" — and a person is one word, because a surname the app
        // guessed at is a different person.
        let target: String = {
            guard kind == .place, words.count >= 2 else { return first }
            let pair = words.prefix(2).joined(separator: " ")
            return trades.contains(words[1]) || trades.contains(first)
                ? pair
                : first
        }()

        return Extraction(target: target, kind: kind)
    }
}
