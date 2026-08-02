//
//  MOCController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 26/12/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import CoreData

class MOCController: NSObject {

    public static let sharedInstance = MOCController()

    // MARK: - Core Data stack
    //
    // MOCController is the single owner of the Core Data stack. This avoids
    // relying on NSApp.delegate, which under the SwiftUI App lifecycle is
    // SwiftUI's own internal AppDelegate rather than our AppDelegate.
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "MessagesHistoryBrowser")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unresolved error \(error)")
            }
        }
        return container
    }()

    var managedObjectContext:NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    override init() {
    }

    func save()
    {
        let context = persistentContainer.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                NSLog("Error saving context: \(error)")
            }
        }
    }

    func clearAllCoreData()
    {
//        let allContacts = ChatContact.allContacts()
//
//        for contact in allContacts {
//            managedObjectContext.delete(contact)
//        }

        let contactsFetchRequest = ChatContact.fetchRequest() // NSFetchRequest<NSFetchRequestResult>(entityName: "Contact")

        let deleteContactsRequest = NSBatchDeleteRequest(fetchRequest: contactsFetchRequest)

        do {
            let context = workerContext()
            try context.execute(deleteContactsRequest)
            try context.save()
        } catch let error {
            NSLog("ERROR when deleting contacts : \(error)")
        }

    }

    func workerContext() -> NSManagedObjectContext
    {
        return persistentContainer.newBackgroundContext()
    }

}
