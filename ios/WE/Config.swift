import Foundation

/// Backend configuration for WE (Supabase project "we-round1").
/// The publishable/anon key is safe to ship in the client — row-level security
/// protects the data. Move to an .xcconfig before a real App Store build.
enum Config {
    static let supabaseURL = URL(string: "https://tizunrayxyorzrvopnsw.supabase.co")!
    static let supabaseAnonKey = "sb_publishable__suAVQyAW3B9BmcN7srkrA_ZlIfZxuY"
}
