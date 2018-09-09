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

    var managedObjectContext:NSManagedObjectContext {
        let appDelegate = NSApp.delegate as! AppDelegate
        return appDelegate.persistentContainer.viewContext
    }

    override init() {
    }

    func save()
    {
        let appDelegate = NSApp.delegate as! AppDelegate
        appDelegate.saveAction(self)
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
            try workerContext().execute(deleteContactsRequest)
        } catch let error {
            NSLog("ERROR when deleting contacts : \(error)")
        }

    }

    func workerContext() -> NSManagedObjectContext
    {
        let appDelegate = NSApp.delegate as! AppDelegate

        let worker = appDelegate.persistentContainer.newBackgroundContext()

        return worker
    }

}
