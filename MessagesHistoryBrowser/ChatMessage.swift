//
//  ChatMessage.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 04/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import CoreData

class ChatMessage : NSManagedObject {

    static let EntityName = "Message"

    enum Attributes:String {
        case content = "content"
        case date = "date"
        case chat = "chat"
    }

    @NSManaged var content:String?

    @NSManaged var date:NSDate

    @NSManaged var chat:Chat

    convenience init(managedObjectContext:NSManagedObjectContext, withMessage aMessage:String, withDate aDate:NSDate, inChat aChat:Chat) {

        let entityDescription = NSEntityDescription.entityForName(ChatMessage.EntityName, inManagedObjectContext: managedObjectContext)
        self.init(entity: entityDescription!, insertIntoManagedObjectContext: managedObjectContext)

        content = aMessage
        date = aDate
        chat = aChat
    }

}
