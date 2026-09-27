//
//  ChatContact.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 10/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import CoreData

class ChatContact: NSManagedObject {

    @NSManaged var identifier:String
    @NSManaged var name:String
    @NSManaged var known:Bool

    @NSManaged var chats:NSSet
    @NSManaged var messages:NSSet
    @NSManaged var attachments:NSSet

    static let sortDescriptor = NSSortDescriptor(key: "name", ascending: true)


    convenience init(managedObjectContext:NSManagedObjectContext, withName aName:String, withIdentifier anIdentifier:String) {

        let entityDescription = NSEntityDescription.entity(forEntityName: "Contact", in: managedObjectContext)
        self.init(entity: entityDescription!, insertInto: managedObjectContext)

        name = aName
        identifier = anIdentifier
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

    class func allKnownContacts(_ managedObjectContext:NSManagedObjectContext) -> [ChatContact] {

        return allContactsWithPredicate(managedObjectContext, predicate:NSPredicate(format: "known == YES && messages.@count > 0"))
    }

    class func allUnknownContacts(_ managedObjectContext:NSManagedObjectContext) -> [ChatContact] {

        return allContactsWithPredicate(managedObjectContext, predicate:NSPredicate(format: "known == NO && messages.@count > 0"))
    }

    class func allContactsWithPredicate(_ managedObjectContext:NSManagedObjectContext, predicate:NSPredicate? = nil) -> [ChatContact] {

        var allContacts = [ChatContact]()

        managedObjectContext.performAndWait { () -> Void in

            do {
                let contactFetchRequest = ChatContact.fetchRequest() // NSFetchRequest<NSFetchRequestResult>(entityName: "Contact")
                contactFetchRequest.predicate = predicate
                contactFetchRequest.sortDescriptors = [ChatContact.sortDescriptor]
                
                let results = try managedObjectContext.fetch(contactFetchRequest)
                allContacts = results as! [ChatContact]
            } catch let error as NSError {
                print("\(#function) : Could not fetch \(error), \(error.userInfo)")
            }
        }

        return allContacts
    }

    class func allContacts(_ managedObjectContext:NSManagedObjectContext) -> [ChatContact] {
        return allContactsWithPredicate(managedObjectContext)
    }

    // Finds the existing ChatContact for a chat handle, or creates one.
    //
    // Known contacts (resolved through the Contacts framework) are matched on
    // their CNContact identifier, so two distinct address book entries that
    // happen to share a display name stay separate. Unknown contacts have an
    // empty identifier and use the raw handle (phone number / email) as their
    // name, so matching on the name is exact for them.
    class func contactIn(_ managedObjectContext:NSManagedObjectContext, named name:String, withIdentifier identifier:String) -> ChatContact {
        let contactNamedFetchRequest = ChatContact.fetchRequest() // NSFetchRequest<NSFetchRequestResult>(entityName: "Contact")
        if identifier.isEmpty {
            contactNamedFetchRequest.predicate = NSPredicate(format: "identifier == '' AND name == %@", name)
        } else {
            contactNamedFetchRequest.predicate = NSPredicate(format: "identifier == %@", identifier)
        }

        var res:ChatContact?

        managedObjectContext.performAndWait { () -> Void in

            do {
                let r = try managedObjectContext.fetch(contactNamedFetchRequest)
                let foundContacts = r as! [ChatContact]

                if foundContacts.count > 0 {
                    res = foundContacts[0]
                } else {
                    res = ChatContact(managedObjectContext: managedObjectContext, withName: name, withIdentifier: identifier)
                }
            } catch let error as NSError {
                print("\(#function) : Could not fetch \(error), \(error.userInfo)")

                res = ChatContact(managedObjectContext: managedObjectContext, withName: name, withIdentifier: identifier)
            }
        }

        return res!
    }

}
