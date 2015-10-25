//
//  MessageFormatter.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 18/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class MessageFormatter {

    let dateFormatter = NSDateFormatter()

    var noMessageString = "<no message>"
    var meString = "me"
    var unknownContact = "<unknown>"

    init() {
        dateFormatter.timeStyle = .ShortStyle
        dateFormatter.dateStyle = .ShortStyle
    }

    func formatMessage(message:ChatMessage) -> String
    {
        let messageContent = message.content ?? noMessageString
        let sender = message.isFromMe ? meString : message.chat.contact.name
        let dateString = dateFormatter.stringFromDate(message.date)

        let messageContentAndSender = "\(dateString) - \(sender) : \(messageContent)"

        return messageContentAndSender
    }

}
