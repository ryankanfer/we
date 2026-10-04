//
//  FieldSmartClassifier.swift
//  WE
//
//  A second opinion from Apple Intelligence, on device, for the captures the
//  rules are unsure of. The rules still file everything first and instantly;
//  this only ever moves an item the rules guessed at, only into a list the
//  couple already has, and never over a correction somebody made. Nothing
//  leaves the phone.
//
//  Phones without Apple Intelligence never reach this file's model. For
//  them, the rules are the whole answer, and an unsure capture lands in
//  Notes instead of being guessed into a list.
//

import Foundation
import FoundationModels

enum FieldSmartClassifier {
    /// True only on a phone where the on-device model is ready right now.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// One list name from `categories`, or nil when the model is unavailable,
    /// unsure, or answers with anything that is not one of them.
    static func category(
        for text: String,
        among categories: [LifeCategory]
    ) async -> LifeCategory? {
        guard isAvailable, !categories.isEmpty else { return nil }
        let names = categories.map(\.rawValue)
        let instructions = """
            You file one short note written by one half of a couple into \
            exactly one of these lists: \(names.joined(separator: ", ")).
            Answer with the list name only, exactly as written, nothing else.
            watchlist is only for films, shows and series.
            buys is anything to purchase, including groceries and household things.
            food is places to eat and things to cook or crave.
            trips is places to go, and a place name with dates is always trips.
            care is people and appointments.
            notes is for anything that fits none of the others.
            """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: text,
                options: GenerationOptions(temperature: 0)
            )
            let answer = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                .lowercased()
            return categories.first { $0.rawValue.lowercased() == answer }
        } catch {
            return nil
        }
    }
}
