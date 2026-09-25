//
//  MessagesHistoryBrowserApp.swift
//  MessagesHistoryBrowser
//
//  SwiftUI App Entry Point
//

import SwiftUI


@main
struct MessagesHistoryBrowserApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, appState.persistentContainer.viewContext)
                .environmentObject(appState)
        }
        .commands {
            AppCommands()
        }
    }
}

// App-level state management
@MainActor
class AppState: ObservableObject {
    @Published var showChatsFromUnknown = false
    @Published var isRefreshingHistory = false
    @Published var needDBReload = false
    
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
