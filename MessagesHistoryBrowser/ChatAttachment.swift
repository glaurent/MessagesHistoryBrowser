//
//  ChatAttachment.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 10/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import CoreData

class ChatAttachment: ChatItem {

    @NSManaged var fileName:String?
    @NSManaged var chat:Chat
    @NSManaged var contact:ChatContact

    convenience init(managedObjectContext:NSManagedObjectContext, withFileName aFileName:String, withDate aDate:NSDate, inChat aChat:Chat) {

        let entityDescription = NSEntityDescription.entityForName("Attachment", inManagedObjectContext: managedObjectContext)
        self.init(entityDescription: entityDescription!, managedObjectContext: managedObjectContext, withDate: aDate)

        fileName = aFileName
        chat = aChat
        contact = aChat.contact
    }
    
}
