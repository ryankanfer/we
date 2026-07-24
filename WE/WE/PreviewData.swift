//
//  PreviewData.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import Foundation

enum PreviewData {
    static let members: [Member] = [
        Member(id: "ryan", name: "Ryan", hue: .burgundy),
        Member(id: "dylan", name: "Dylan", hue: .sage)
    ]

    static let insights: [Insight] = [
        Insight(
            id: "saturday-plan",
            kind: .logistical,
            domain: .life,
            present: true,
            title: "Saturday is filling up.",
            body: "3 errands · dinner at 7:00",
            evidence: "Three errands and one dinner plan reference Saturday.",
            source: "Plans",
            actionTitle: "Shape a plan",
            options: [
                "Make one efficient route",
                "Split the errands",
                "Protect part of the day"
            ]
        ),
        Insight(
            id: "august-trip",
            kind: .unresolved,
            domain: .us,
            present: true,
            title: "The August trip is still open.",
            body: "Set aside twice · last discussed 9 days ago",
            evidence: "The trip was saved twice without a shared decision.",
            source: "Shared continuity",
            actionTitle: "Open together",
            options: [
                "Choose a time to discuss it",
                "Look at the saved ideas",
                "Set it aside for now"
            ]
        )
    ]
}
