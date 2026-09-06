//
//  WEArrivalNotifications.swift
//  WE
//
//  The one thing WE is allowed to say from a lock screen.
//
//  THE RULE
//
//  **WE never sends a notification containing news, only ones inviting
//  presence.** Not a name, not a decision, not a message, not a count, not
//  anything derived from private material. A notification may say that WE is
//  worth opening now; the app says the rest to somebody who is holding it.
//
//  `sentence` is that sentence. It is fixed, identical for every couple and
//  every arrival, and it is duplicated in `supabase/functions/announce-arrival`
//  because the send happens on a server. `WEArrivalNotificationTests` asserts
//  the two are the same string, so the duplication cannot drift.
//
//  PERMISSION DENIAL IS A FIRST CLASS PATH
//
//  If notifications are refused, the ceremony works identically and the
//  arrival lands the next time the app is opened. There is no re-prompt, no
//  "enable notifications to continue", no degraded state, and no screen that
//  mentions it. This file has no way to ask for permission for exactly that
//  reason: it registers only when permission has *already* been given, for the
//  local moments `FieldMomentDelivery` asks about once, after onboarding.
//
//  THE TOKEN
//
//  Arrives on the app delegate, which has no session, so it waits here until
//  something with a session takes it. It is persisted to a per person, owner
//  only table: a partner must never be able to read the other's, and nothing
//  joins a token to a couple except the worker, with the service role.
//

import Foundation

#if canImport(UIKit)
import UIKit
import UserNotifications
#endif

enum WEArrivalNotifications {
    /// The fixed string, and the whole payload.
    ///
    /// Deliberately says nothing about who arrived. The two people know who
    /// they invited; a lock screen is read by whoever is looking at the phone.
    static let sentence = "WE is ready for you both."

    /// Registers for remote notifications, but only if this person has already
    /// said yes to notifications at all.
    ///
    /// Never asks. Asking is `FieldMomentDelivery.requestAuthorization`, which
    /// happens once, after onboarding, on the person's way in — and if the
    /// answer was no, this returns and the product is unchanged.
    @MainActor
    static func registerIfPermitted() async {
        #if canImport(UIKit)
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else { return }
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// The token as APNs wants it written down.
    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}

/// Where a device token waits for something that can spend it.
///
/// The delegate callback can land before there is a session, after a sign out,
/// or twice in a launch when iOS reissues one. Holding the latest value and
/// telling whoever is listening covers all three without the delegate knowing
/// anything about accounts.
@MainActor
final class WEDeviceTokenStore {
    static let shared = WEDeviceTokenStore()

    private(set) var latest: String?

    /// Set by `AppSession`, which is the only thing that can write a token to
    /// a person. Called immediately if a token is already in hand.
    var onToken: ((String) -> Void)? {
        didSet {
            if let latest { onToken?(latest) }
        }
    }

    func received(_ token: String) {
        guard latest != token else { return }
        latest = token
        onToken?(token)
    }

    /// A sign out takes the device with it. What is forgotten here is only
    /// this side of it; the row is deleted through `forget_device_tokens`.
    func forget() {
        latest = nil
    }
}
