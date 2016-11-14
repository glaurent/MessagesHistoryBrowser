//
//  ChatMessage.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 04/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import CoreData

class ChatMessage : ChatItem {

    static let EntityName = "Message"

    enum Attributes:String {
        case content = "content"
        case date = "date"
        case chat = "chat"
        case isFromMe = "isFromMe"
    }

    @NSManaged var content:String?
    @NSManaged var isFromMe:Bool

    @NSManaged var chat:Chat
    @NSManaged var contact:ChatContact

    convenience init(managedObjectContext:NSManagedObjectContext, withMessage aMessage:String, withDate aDate:Date, inChat aChat:Chat) {

        let entityDescription = NSEntityDescription.entity(forEntityName: ChatMessage.EntityName, in: managedObjectContext)
        self.init(entityDescription: entityDescription!, managedObjectContext: managedObjectContext, withDate:aDate)

        content = aMessage
        chat = aChat
        contact = aChat.contact
    }

}
