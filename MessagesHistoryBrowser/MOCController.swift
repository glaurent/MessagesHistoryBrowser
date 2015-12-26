//
//  MOCController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 26/12/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class MOCController: NSObject {

    static let sharedInstance = MOCController()

    var managedObjectContext:NSManagedObjectContext!
    var privateManagedObjectContext:NSManagedObjectContext!

    override init() {
        let coordinator = (NSApp.delegate as! AppDelegate).persistentStoreCoordinator

        managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        privateManagedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        privateManagedObjectContext.persistentStoreCoordinator = coordinator

        managedObjectContext.parentContext = privateManagedObjectContext
    }

    func save()
    {
        guard privateManagedObjectContext.hasChanges || managedObjectContext.hasChanges else { return }

        managedObjectContext.performBlockAndWait { () -> Void in
            do { try self.managedObjectContext.save() } catch { NSLog("moc save error : \(error)") }

            self.privateManagedObjectContext.performBlock { () -> Void in
                do { try self.privateManagedObjectContext.save() } catch { NSLog("bgMoc save error : \(error)") }
            }
        }
    }

    func clearAllCoreData() {

        let allContacts = ChatContact.allContactsInContext(managedObjectContext)

        for contact in allContacts {
            managedObjectContext.deleteObject(contact)
        }

    }

}
