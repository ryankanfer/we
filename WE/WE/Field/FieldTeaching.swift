//
//  FieldTeaching.swift
//  WE
//
//  The identifiers for things this app says to a person exactly once.
//
//  Kept in one file, and kept as fixed lower-camel strings, for two reasons.
//  The keys travel to `field_teaching_moments`, a table both a person and the
//  database can read, so anything descriptive in one would put rendered copy in
//  a row — and the check constraint on that column refuses it anyway. And a
//  moment that is spelled differently in two places is a moment that happens
//  twice, which is the exact failure this table exists to prevent.
//
enum FieldTeaching {
    /// Us has changed into a living journey for the first time.
    static let journeyOpened = "journeyOpened"
    /// A capability has appeared for the first time in this person's life with
    /// the product — not the first time in this journey.
    static let firstCapability = "firstCapability"
}
