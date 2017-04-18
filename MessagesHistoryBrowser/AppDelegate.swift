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

    var needDBReload = false

    var showChatsFromUnknown = false {
        didSet {
            NSLog("showChatsFromUnknown set")
            NotificationCenter.default.post(name: Notification.Name(rawValue: AppDelegate.ShowChatsFromUnknownNotification), object: self)
        }
    }

    var chatTableViewController:ChatTableViewController?

    var hasChatSelected:Bool {
        get {
            return chatTableViewController?.hasChatSelected ?? false
        }
    }

    dynamic var isChatSelected:Bool {
        get {
            guard let chatTableViewController = chatTableViewController else { return false }
            return chatTableViewController.tableView.selectedRow >= 0 && chatTableViewController.tableView.selectedRowIndexes.count == 1
        }
    }
    dynamic var isRefreshingHistory = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application        
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    // MARK: - Core Data stack

    lazy var applicationDocumentsDirectory: URL = {
        // The directory the application uses to store the Core Data store file. This code uses a directory named "org.telegraph-road.MessagesHistoryBrowser" in the user's Application Support directory.
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = urls[urls.count - 1]
        return appSupportURL.appendingPathComponent("org.telegraph-road.MessagesHistoryBrowser")
    }()

    lazy var managedObjectModel: NSManagedObjectModel = {
        // The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
        let modelURL = Bundle.main.url(forResource: "MessagesHistoryBrowser", withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: modelURL)!
    }()

    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
        // The persistent store coordinator for the application. This implementation creates and returns a coordinator, having added the store for the application to it. (The directory for the store is created, if necessary.) This property is optional since there are legitimate error conditions that could cause the creation of the store to fail.
        let fileManager = FileManager.default
        var failError: NSError? = nil
        var shouldFail = false
        var failureReason = "There was an error creating or loading the application's saved data."

        // Make sure the application files directory is there
        do {
            let properties = try (self.applicationDocumentsDirectory as NSURL).resourceValues(forKeys: [URLResourceKey.isDirectoryKey])
            if !(properties[URLResourceKey.isDirectoryKey]! as AnyObject).boolValue {
                failureReason = "Expected a folder to store application data, found a file \(self.applicationDocumentsDirectory.path)."
                shouldFail = true
            }
        } catch  {
            let nserror = error as NSError
            
            if nserror.code == NSFileReadNoSuchFileError {
                do {
                    try fileManager.createDirectory(atPath: self.applicationDocumentsDirectory.path, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    failError = nserror
                }
            } else {
                failError = nserror
            }
        }
        
        // Create the coordinator and store
        var coordinator: NSPersistentStoreCoordinator? = nil
        if failError == nil {
            coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
            let url = self.applicationDocumentsDirectory.appendingPathComponent("CocoaAppCD.storedata")
            do {
                let persistentStoreOptions = [
                    NSMigratePersistentStoresAutomaticallyOption : true,
                    NSInferMappingModelAutomaticallyOption : true
                ]
                try coordinator!.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: persistentStoreOptions)
            } catch {
//                failError = error as! NSError
                self.needDBReload = true
            }
        }
        
        if shouldFail || (failError != nil) {
            // Report any error we got.
            var dict = [String: AnyObject]()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data" as AnyObject?
            dict[NSLocalizedFailureReasonErrorKey] = failureReason as AnyObject?
            if failError != nil {
                dict[NSUnderlyingErrorKey] = failError
            }
            let error = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            NSApplication.shared().presentError(error)
            abort()
        } else {
            return coordinator!
        }
    }()

    // Moved to MOCController
    //
//    lazy var managedObjectContext: NSManagedObjectContext = {
//        // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.) This property is optional since there are legitimate error conditions that could cause the creation of the context to fail.
//        let coordinator = self.persistentStoreCoordinator
//        var managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
//        managedObjectContext.persistentStoreCoordinator = coordinator
//        return managedObjectContext
//    }()

    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(_ sender: AnyObject!) {

        let managedObjectContext = MOCController.sharedInstance.managedObjectContext

        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        if !(managedObjectContext.commitEditing()) {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
        }
        if (managedObjectContext.hasChanges) {
            do {
                try managedObjectContext.save()
            } catch {
                let nserror = error as NSError
                NSApplication.shared().presentError(nserror)
            }
        }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return MOCController.sharedInstance.managedObjectContext.undoManager
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplicationTerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        let managedObjectContext = MOCController.sharedInstance.managedObjectContext

        if !(managedObjectContext.commitEditing()) {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing to terminate")
            return .terminateCancel
        }
        
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
            if answer == NSAlertFirstButtonReturn {
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

        if let mainWindow = NSApplication.shared().mainWindow {

            savePanel.beginSheetModal(for: mainWindow, completionHandler: { (action) in
                guard action == NSFileHandlingPanelOKButton else { return }
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

