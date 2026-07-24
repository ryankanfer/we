//
//  PreviewData.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import Foundation

enum PreviewData {
    static let members: [Member] = [
        Member(id: "ry", name: "Ry", hue: .burgundy),
        Member(id: "alex", name: "Alex", hue: .sage)
    ]

    static let insight = Insight(
        id: "saturday-errands",
        kind: .logistical,
        domain: .life,
        present: true,
        title: "Three errands are competing for Saturday.",
        body: """
        The pharmacy pickup, hardware return, and grocery run are all \
        pointing at the same morning. Folded together, they are one loop.
        """,
        evidence: "Three open tasks reference Saturday.",
        source: "Task list · recent Saturdays",
        options: [
            "Fold them into one plan",
            "Split them between us",
            "Leave Saturday open"
        ]
    )
}
