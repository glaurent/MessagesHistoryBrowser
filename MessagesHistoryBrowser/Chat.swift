//
//  Chat.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 27/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import CoreData

class Chat : NSManagedObject {

    @NSManaged var contact:ChatContact?

    @NSManaged var guid:String

    @NSManaged var rowID:NSNumber

    @NSManaged var messages:NSSet

    @NSManaged var attachments:NSSet


    convenience init(managedObjectContext:NSManagedObjectContext, withContact aContact:ChatContact, withGUID aGuid:String, andRowID aRowID:Int) {

        let entityDescription = NSEntityDescription.entityForName("Chat", inManagedObjectContext: managedObjectContext)
        self.init(entity: entityDescription!, insertIntoManagedObjectContext: managedObjectContext)

        contact = aContact
        guid = aGuid
        rowID = aRowID
    }

    class func allChatsInContext(managedObjectContext:NSManagedObjectContext) -> [Chat] {
        let fetchRequest = NSFetchRequest(entityName: "Chat")

        var allChats = [Chat]()

        do {
            let results = try managedObjectContext.executeFetchRequest(fetchRequest)
            allChats = results as! [Chat]
        } catch let error as NSError {
            print("\(__FUNCTION__) : Could not fetch \(error), \(error.userInfo)")
        }

        return allChats
    }

}

