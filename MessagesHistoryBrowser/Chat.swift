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

        let entityDescription = NSEntityDescription.entity(forEntityName: "Chat", in: managedObjectContext)
        self.init(entity: entityDescription!, insertInto: managedObjectContext)

        contact = aContact
        serviceName = aServiceName
        guid = aGuid
        rowID = NSNumber(value:aRowID)
    }

    class func numberOfChatsInContext(_ managedObjectContext:NSManagedObjectContext) -> Int {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Chat")

        var res:Int = 0

        managedObjectContext.performAndWait { () -> Void in
            res = try! managedObjectContext.count(for: fetchRequest)
        }

        return res

    }

    class func allChatsInContext(_ managedObjectContext:NSManagedObjectContext) -> [Chat] {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Chat")

        var allChats = [Chat]()

        managedObjectContext.performAndWait { () -> Void in
            do {
                let results = try managedObjectContext.fetch(fetchRequest)
                allChats = results as! [Chat]
            } catch let error as NSError {
                print("\(#function) : Could not fetch \(error), \(error.userInfo)")
            }
        }

        return allChats
    }

}

