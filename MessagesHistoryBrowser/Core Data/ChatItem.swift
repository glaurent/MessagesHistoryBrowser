//
//  ChatItem.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 02/11/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import CoreData

class ChatItem: NSManagedObject {

    @NSManaged var date:Date              // seconds-precision Date derived from `dateNanoseconds`, for display and Core Data date predicates
    @NSManaged var dateNanoseconds:Int64  // exact source-of-truth timestamp (nanoseconds since the 2001 reference date); use for ordering
    @NSManaged var index:Int64 // used when searching a term in chats, to fetch surrounding messages for a message matching the search term
    @NSManaged var isFromMe:Bool

    convenience init(entityDescription:NSEntityDescription, managedObjectContext:NSManagedObjectContext, withDate aDate:Date) {
        
        self.init(entity: entityDescription, insertInto: managedObjectContext)
        
        date = aDate
    }

}
