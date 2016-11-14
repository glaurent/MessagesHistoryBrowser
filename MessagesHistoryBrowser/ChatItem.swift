//
//  ChatItem.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 02/11/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import CoreData

class ChatItem: NSManagedObject {

    @NSManaged var date:Date
    @NSManaged var index:Int64
    
    convenience init(entityDescription:NSEntityDescription, managedObjectContext:NSManagedObjectContext, withDate aDate:Date) {
        
        self.init(entity: entityDescription, insertInto: managedObjectContext)
        
        date = aDate
    }

}
