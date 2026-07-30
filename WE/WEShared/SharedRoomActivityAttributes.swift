import ActivityKit
import Foundation

struct SharedRoomActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let snapshot: ExternalSurfaceSnapshot
    }

    /// A timestamp is sufficient to identify the activity locally. No person,
    /// relationship, response, or invitation identifier leaves the app.
    let createdAt: Date
}
