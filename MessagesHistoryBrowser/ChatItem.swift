//
//  ChatItem.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 02/11/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import CoreData

class ChatItem: NSManagedObject {

    @NSManaged var date:NSDate

    
    convenience init(entityDescription:NSEntityDescription, managedObjectContext:NSManagedObjectContext, withDate aDate:NSDate) {
        
        self.init(entity: entityDescription, insertIntoManagedObjectContext: managedObjectContext)
        
        date = aDate
    }

}
