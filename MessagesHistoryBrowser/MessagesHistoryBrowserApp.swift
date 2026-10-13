//
//  MessagesHistoryBrowserApp.swift
//  MessagesHistoryBrowser
//
//  SwiftUI App Entry Point
//

import SwiftUI
import Sparkle


@main
struct MessagesHistoryBrowserApp: App {
    @StateObject private var appState = AppState()

    // Owns Sparkle's updater for the app's lifetime. `startingUpdater: true`
    // has it begin life immediately, scheduling automatic checks per the
    // user's preference and the SUFeedURL/SUPublicDSAKeyFile already
    // configured in Info.plist; AppCommands' menu item triggers a manual
    // check against the same updater.
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, appState.persistentContainer.viewContext)
                .environmentObject(appState)
        }
        .commands {
            AppCommands(updater: updaterController.updater)
        }

        // One stats window per contact, keyed by the URI of its object ID;
        // opening it again for the same contact brings the existing window forward.
        WindowGroup("Conversation Stats", id: ConversationStatsView.windowID, for: URL.self) { $contactURI in
            ConversationStatsView(contactURI: contactURI)
        }
        .defaultSize(width: 760, height: 460)
    }
}

// App-level state management
@MainActor
class AppState: ObservableObject {
    @Published var showChatsFromUnknown = false
    @Published var isRefreshingHistory = false
    @Published var needDBReload = false

    // Set after an import when Contacts access was not available, so
    // ContentView can tell the user why chats show numbers and addresses
    // instead of names, rather than failing silently.
    @Published var contactsAccessDenied = false

    static let iCloudStoredAttachmentExtension = "pluginPayloadAttachment"

    let chatsDBPath = "/Users/" + NSUserName() + "/Library/Messages/chat.db"
    var chatsDatabase: ChatsDatabase?
    
    // Core Data stack — shared single source of truth owned by MOCController,
    // so the SwiftUI environment context matches the one used elsewhere.
    var persistentContainer: NSPersistentContainer {
        MOCController.sharedInstance.persistentContainer
    }
    
    init() {
        UserDefaults.standard.register(defaults: [
            ShowDetailedSenderUserDefaultsKey: false,
            ShowTerseTimeUserDefaultsKey: true
        ])
        
        // Initialize chat database
        do {
            try chatsDatabase = ChatsDatabase(chatsDBPath: chatsDBPath)
        } catch {
            NSLog("DB init error: \(error)")
            needDBReload = true
        }
    }
    
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                NSLog("Error saving context: \(nserror)")
            }
        }
    }
}
