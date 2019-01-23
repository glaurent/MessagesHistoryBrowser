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

    static var dateFormatter:DateFormatter = {
        let RFC3339DateFormatter = DateFormatter()

        RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
        RFC3339DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        RFC3339DateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return RFC3339DateFormatter
    }()

    enum Attributes:String {
        case content = "content"
        case date = "date"
        case chat = "chat"
        case isFromMe = "isFromMe"
    }

    @NSManaged var content:String?

    @NSManaged var chat:Chat
    @NSManaged var contact:ChatContact

    convenience init(managedObjectContext:NSManagedObjectContext, withMessage aMessage:String, withDate aDate:Date, inChat aChat:Chat) {

        let entityDescription = NSEntityDescription.entity(forEntityName: ChatMessage.EntityName, in: managedObjectContext)
        self.init(entityDescription: entityDescription!, managedObjectContext: managedObjectContext, withDate:aDate)

        content = aMessage
        chat = aChat
        contact = aChat.contact
    }

    func toJSON() -> Data {
        let objAsDict = toJSONConvertibleDict()

        return try! JSONSerialization.data(withJSONObject: objAsDict, options: .prettyPrinted)
    }

    func toJSONConvertibleDict() -> [String:Any] {

        return [ "date" : ChatMessage.dateFormatter.string(from: date),
                 "me" : isFromMe,
                 "content" : content ?? ""] as [String : Any]
    }
}
