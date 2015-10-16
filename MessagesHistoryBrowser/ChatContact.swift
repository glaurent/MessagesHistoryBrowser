//
//  ChatContact.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 10/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class ChatContact: NSManagedObject {

    @NSManaged var name:String
    @NSManaged var known:Bool

    @NSManaged var chats:NSOrderedSet

    static let fetchRequest = NSFetchRequest(entityName: "Contact")
    static let sortDescriptor = NSSortDescriptor(key: "name", ascending: true)


    convenience init(managedObjectContext:NSManagedObjectContext, withName aName:String) {

        let entityDescription = NSEntityDescription.entityForName("Contact", inManagedObjectContext: managedObjectContext)
        self.init(entity: entityDescription!, insertIntoManagedObjectContext: managedObjectContext)

        name = aName
    }

    class func setupFetchRequest() {
        if (ChatContact.fetchRequest.sortDescriptors == nil) {
            ChatContact.fetchRequest.sortDescriptors = [ChatContact.sortDescriptor]
        }
    }

//    class func allContactsInContext(managedObjectContext:NSManagedObjectContext) -> [ChatContact] {
//
//        var allContacts = [ChatContact]()
//
//        do {
//            let results = try managedObjectContext.executeFetchRequest(fetchRequest)
//            allContacts = results as! [ChatContact]
//        } catch let error as NSError {
//            print("\(__FUNCTION__) : Could not fetch \(error), \(error.userInfo)")
//        }
//
//        return allContacts
//    }

    class func allKnownContactsInContext(managedObjectContext:NSManagedObjectContext) -> [ChatContact] {

        return allContactsInContext(managedObjectContext, withPredicate: NSPredicate(format: "known == YES"))
    }

    class func allUnknownContactsInContext(managedObjectContext:NSManagedObjectContext) -> [ChatContact] {

        return allContactsInContext(managedObjectContext, withPredicate: NSPredicate(format: "known == NO"))
    }

    class func allContactsInContext(managedObjectContext:NSManagedObjectContext, withPredicate predicate:NSPredicate? = nil) -> [ChatContact] {

        ChatContact.setupFetchRequest()

        var allContacts = [ChatContact]()

        do {
            if let predicate = predicate {
                fetchRequest.predicate = predicate
            } else {
                fetchRequest.predicate = nil
            }

            let results = try managedObjectContext.executeFetchRequest(fetchRequest)
            allContacts = results as! [ChatContact]
        } catch let error as NSError {
            print("\(__FUNCTION__) : Could not fetch \(error), \(error.userInfo)")
        }

        return allContacts
    }


    class func contactIn(managedObjectContext:NSManagedObjectContext, named name:String) -> ChatContact {
        let contactNamedFetchRequest = NSFetchRequest(entityName: "Contact")
        let namePredicate = NSPredicate(format: "name == %@", name)
        contactNamedFetchRequest.predicate = namePredicate

        do {
            let r = try managedObjectContext.executeFetchRequest(contactNamedFetchRequest)
            let foundContacts = r as! [ChatContact]

            if foundContacts.count > 0 {
                return foundContacts[0]
            }

            return ChatContact(managedObjectContext: managedObjectContext, withName: name)

        } catch let error as NSError {
            print("\(__FUNCTION__) : Could not fetch \(error), \(error.userInfo)")

            return ChatContact(managedObjectContext: managedObjectContext, withName: name)
        }

    }

}
