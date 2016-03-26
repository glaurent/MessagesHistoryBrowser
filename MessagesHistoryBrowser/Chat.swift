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

    @NSManaged var contact:ChatContact

    @NSManaged var serviceName:String

    @NSManaged var guid:String

    @NSManaged var rowID:NSNumber

    @NSManaged var messages:NSSet

    @NSManaged var attachments:NSSet


    convenience init(managedObjectContext:NSManagedObjectContext, withContact aContact:ChatContact, withServiceName aServiceName:String, withGUID aGuid:String, andRowID aRowID:Int) {

        let entityDescription = NSEntityDescription.entityForName("Chat", inManagedObjectContext: managedObjectContext)
        self.init(entity: entityDescription!, insertIntoManagedObjectContext: managedObjectContext)

        contact = aContact
        serviceName = aServiceName
        guid = aGuid
        rowID = aRowID
    }

    class func numberOfChatsInContext(managedObjectContext:NSManagedObjectContext) -> Int {
        let fetchRequest = NSFetchRequest(entityName: "Chat")

        var res:Int = 0

        var err:NSError?

        managedObjectContext.performBlockAndWait { () -> Void in
            res = managedObjectContext.countForFetchRequest(fetchRequest, error: &err)
        }

        return res

    }

    class func allChatsInContext(managedObjectContext:NSManagedObjectContext) -> [Chat] {
        let fetchRequest = NSFetchRequest(entityName: "Chat")

        var allChats = [Chat]()

        managedObjectContext.performBlockAndWait { () -> Void in
            do {
                let results = try managedObjectContext.executeFetchRequest(fetchRequest)
                allChats = results as! [Chat]
            } catch let error as NSError {
                print("\(#function) : Could not fetch \(error), \(error.userInfo)")
            }
        }

        return allChats
    }

}

