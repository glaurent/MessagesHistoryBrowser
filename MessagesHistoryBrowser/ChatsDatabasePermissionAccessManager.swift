//
//  ChatsDatabasePermissionAccessManager.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 02/11/2026.
//  Copyright © 2026 Guillaume Laurent. All rights reserved.
//

import Foundation
import SwiftUI

class ChatsDatabasePermissionAccessManager {
    static let sharedInstance = ChatsDatabasePermissionAccessManager()

    let userDefaultsBookmarkKey = "messagesFolderBookmark"
    let chatsFolderPath = NSHomeDirectory() + "/Library/Messages"
    let chatsDBPath: String
    var chatsDatabase: ChatsDatabase?

    private init() {
        chatsDBPath = chatsFolderPath + "/chat.db"

    }

    @MainActor
    func checkDatabaseFolderAccess() async -> Bool {
        if resolveMessagesFolderBookmark() != nil {
            return true
        }

        if let folderURL = await requestMessagesFolderAccess() {
            _ = folderURL.startAccessingSecurityScopedResource()   // keep for app lifetime
            return true
        }

        return false
    }

    private func resolveMessagesFolderBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsBookmarkKey) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                        relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    @MainActor
    private func requestMessagesFolderAccess() async -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Select your Messages folder so MessagesHistoryBrowser can read your chat history."
        panel.prompt = "Grant Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true   // ~/Library is hidden in Finder
        panel.directoryURL = URL(filePath: chatsFolderPath)

        guard await panel.begin() == .OK, let url = panel.url else { return nil }

        // Save a bookmark so you don't have to ask again on every launch.
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: userDefaultsBookmarkKey)
        }

        return url
    }


}
