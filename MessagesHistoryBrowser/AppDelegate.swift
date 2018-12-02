//
//  AppDelegate.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 27/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    static let ShowChatsFromUnknownNotification = "ShowChatsFromUnknownNotification"

    let chatsDBPath = "/Users/" + NSUserName() + "/Library/Messages/chat.db"  // NSString(string:"~/Library/Messages/chat.db").expandingTildeInPath // this won't work in sandboxed environment

    var chatsDatabase:ChatsDatabase?

    var needDBReload = false

    @objc var showChatsFromUnknown = false {
        didSet {
            NSLog("showChatsFromUnknown set")
            NotificationCenter.default.post(name: Notification.Name(rawValue: AppDelegate.ShowChatsFromUnknownNotification), object: self)
        }
    }

    var chatTableViewController:ChatTableViewController?

    @objc var hasChatSelected:Bool {
        get {
            return chatTableViewController?.hasChatSelected ?? false
        }
    }

    @objc dynamic var isChatSelected:Bool {
        get {
            guard let chatTableViewController = chatTableViewController else { return false }
            return chatTableViewController.tableView.selectedRow >= 0 && chatTableViewController.tableView.selectedRowIndexes.count == 1
        }
    }
    
    @objc dynamic var isRefreshingHistory = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application

        // moved to ChatTableViewController.setupChatDatabase()
        //
//        do {
//            try chatsDatabase = ChatsDatabase(chatsDBPath:chatsDBPath)
//        } catch let error {
//            NSLog("DB init error : \(error)")
//
//            if #available(OSX 10.14, *) {
//
//                let showAppPrivilegesSetupWindowController = NSStoryboard.main?.instantiateController(withIdentifier: "AccessPrivilegesDialog") as! NSWindowController
//
//                NSApp.mainWindow?.beginSheet(showAppPrivilegesSetupWindowController.window!, completionHandler: { (_) in
//                    NSApp.terminate(nil)
//                })
//
//            } else {
//                let alert = NSAlert()
//                alert.messageText = String(format:NSLocalizedString("Couldn't open Messages.app database in\n%@", comment: ""), chatsDBPath)
//                alert.informativeText = NSLocalizedString("Application can't run. Check if the database is accessible", comment: "")
//                alert.alertStyle = .critical
//                alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
//                let _ = alert.runModal()
//                NSApp.terminate(nil)
//            }
//        }

        UserDefaults.standard.register(defaults: [ShowDetailedSenderUserDefaultsKey : false, ShowTerseTimeUserDefaultsKey : true])
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
         */
        let container = NSPersistentContainer(name: "MessagesHistoryBrowser")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(_ sender: AnyObject?) {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        let context = persistentContainer.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Customize this code block to include application-specific recovery steps.
                let nserror = error as NSError
                NSApplication.shared.presentError(nserror)
            }
        } else {
//            NSLog("\(#function) : no change in viewContext")
        }
    }


    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return MOCController.sharedInstance.managedObjectContext.undoManager
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        let managedObjectContext = MOCController.sharedInstance.managedObjectContext

        if !(managedObjectContext.hasChanges) {
            return .terminateNow
        }
        
        do {
            try managedObjectContext.save()
        } catch {
            let nserror = error as NSError
            // Customize this code block to include application-specific recovery steps.
            let result = sender.presentError(nserror)
            if (result) {
                return .terminateCancel
            }
            
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButton(withTitle: quitButton)
            alert.addButton(withTitle: cancelButton)
            
            let answer = alert.runModal()
            if answer == NSApplication.ModalResponse.alertFirstButtonReturn {
                return .terminateCancel
            }
        }
        // If we got here, it is time to quit.
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: Actions

    @IBAction func refreshChatHistory(_ sender: AnyObject) {
        isRefreshingHistory = true
        chatTableViewController?.refreshChatHistory()
    }

    @IBAction func exportSelectedChatToJSON(_ sender: AnyObject) {

        guard let (contact, messages) = chatTableViewController?.orderedMessagesForSelectedRow() else { return }

        let messagesAsDicts = messages.map { $0.toJSONConvertibleDict() }

        let dict:[String:Any] = ["contact" : contact.name, "messages" : messagesAsDicts]

        let savePanel = NSSavePanel()

        if let mainWindow = NSApplication.shared.mainWindow {

            savePanel.beginSheetModal(for: mainWindow, completionHandler: { (action) in
                guard action.rawValue == NSFileHandlingPanelOKButton else { return }
                guard let fileURL = savePanel.url else { return }

                do {

                    let jsonDataToSave = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
                    try jsonDataToSave.write(to: fileURL)

                } catch let error {
                    NSLog("error while exporting to JSON : " + error.localizedDescription)
                }

            })

        }
    }

}

