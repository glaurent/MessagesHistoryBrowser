//
//  ContactAvatarCache.swift
//  MessagesHistoryBrowser
//
//  Off-main-thread, memoized access to contact avatars.
//

import Cocoa

// What a contact row displays next to the name.
enum ContactAvatar {
    case image(NSImage)      // the contact's photo, already rounded
    case initials(String)    // no photo: first letters of given and family names
    case none                // unknown contact, or lookup failed
}

// Contacts framework lookups (CNContactStore.unifiedContact) are IPC round
// trips to the contacts daemon, costing milliseconds each. SwiftUI recreates
// List rows as they scroll into view, so performing that lookup synchronously
// in a row's onAppear stalls scrolling. This actor moves the lookup off the
// main thread and caches the result per contact identifier, so each contact
// is fetched at most once per launch even as its row is recreated repeatedly.
actor ContactAvatarCache {

    static let shared = ContactAvatarCache()

    // ContactRow shows the avatar at 32 points; 64 pixels covers that at 2x
    // (Retina) and is still sharp downscaled on a 1x display. Fixed rather
    // than scale-aware, since this one size is the only place avatars appear.
    private static let avatarPixelSize = 64

    private var cache: [String: ContactAvatar] = [:]

    // Lookups already running, so concurrent requests for the same contact
    // (e.g. a row recreated while its first fetch is still in flight) share
    // one fetch instead of each hitting the contact store.
    private var inFlight: [String: Task<ContactAvatar, Never>] = [:]

    func avatar(for contactIdentifier: String) async -> ContactAvatar {
        if let cached = cache[contactIdentifier] {
            return cached
        }
        if let pending = inFlight[contactIdentifier] {
            return await pending.value
        }

        // Detached so the fetch runs on a background thread rather than the
        // caller's (main) context, and so it completes and populates the cache
        // even if the requesting row scrolls away and its task is cancelled.
        let task = Task.detached(priority: .userInitiated) {
            ContactAvatarCache.loadAvatar(for: contactIdentifier)
        }
        inFlight[contactIdentifier] = task

        let avatar = await task.value
        cache[contactIdentifier] = avatar
        inFlight[contactIdentifier] = nil
        return avatar
    }

    private static func loadAvatar(for contactIdentifier: String) -> ContactAvatar {
        // Unknown contacts carry an empty identifier; there is nothing to look up.
        guard !contactIdentifier.isEmpty else { return .none }

        let (image, initialsPair) = ContactsMap.sharedInstance.contactImage(contactIdentifier)

        if let image = image, let rounded = roundCorners(image, maxPixelSize: avatarPixelSize) {
            return .image(rounded)
        } else if let initialsPair = initialsPair {
            return .initials("\(initialsPair.0)\(initialsPair.1)")
        }
        return .none
    }
}
