//
//  MOCController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 26/12/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class MOCController: NSObject {

    public static let sharedInstance = MOCController()

    var managedObjectContext:NSManagedObjectContext
    var privateManagedObjectContext:NSManagedObjectContext

    override init() {
        let coordinator = (NSApp.delegate as! AppDelegate).persistentStoreCoordinator

        managedObjectContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        privateManagedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateManagedObjectContext.persistentStoreCoordinator = coordinator

        managedObjectContext.parent = privateManagedObjectContext
    }

    func save()
    {
        guard privateManagedObjectContext.hasChanges || managedObjectContext.hasChanges else { return }

        managedObjectContext.performAndWait { [unowned self] () -> Void in

            do { try self.managedObjectContext.save() } catch { NSLog("moc save error : \(error)") }

            self.privateManagedObjectContext.perform { () -> Void in
                do { try self.privateManagedObjectContext.save() } catch { NSLog("bgMoc save error : \(error)") }
            }
        }
    }

    func clearAllCoreData()
    {
        let allContacts = ChatContact.allContactsInContext(managedObjectContext)

        for contact in allContacts {
            managedObjectContext.delete(contact)
        }
    }

    func workerContext() -> NSManagedObjectContext
    {
        let worker = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        worker.parent = managedObjectContext

        return worker
    }

}
