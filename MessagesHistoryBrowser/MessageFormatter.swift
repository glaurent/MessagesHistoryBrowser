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
    let fullDateFormatter = NSDateFormatter()
    
    let noMessageString = "<no message>"
    let meString = "me"
    let unknownContact = "<unknown>"

    var terseTimeMode:Bool {
        didSet {
            dateFormatter.dateStyle = terseTimeMode ? .NoStyle : .ShortStyle
        }
    }
    
    init() {
        dateFormatter.timeStyle = .ShortStyle
        dateFormatter.dateStyle = .NoStyle
        
        fullDateFormatter.timeStyle = .LongStyle
        fullDateFormatter.dateStyle = .LongStyle

        terseTimeMode = true
    }

//    func formatMessage(message:ChatMessage) -> String
//    {
//        let messageContent = message.content ?? noMessageString
//        let sender = message.isFromMe ? meString : message.chat.contact.name
//        let dateString = dateFormatter.stringFromDate(message.date)
//
//        let messageContentAndSender = "\(dateString) - \(sender) : \(messageContent)"
//
//        return messageContentAndSender
//    }


    func formatMessage(message:ChatMessage, withHighlightTerm highlightTerm:String? = nil) -> NSAttributedString?
    {
        guard let messageContent = message.content else { return nil }
        guard messageContent != "" else { return nil }

        let chatContact = message.contact

        let sender:NSMutableAttributedString

        if message.isFromMe {
            sender = NSMutableAttributedString(string: meString, attributes: [NSBackgroundColorAttributeName : NSColor.greenColor()])
        } else {
            sender = NSMutableAttributedString(string: chatContact.name , attributes: [NSBackgroundColorAttributeName : NSColor.blueColor()])
        }

        let dateString = NSMutableAttributedString(string: dateFormatter.stringFromDate(message.date))

        let result = dateString
        result.appendAttributedString(NSAttributedString(string: " - "))
        result.appendAttributedString(sender)

        // highlight message content
        //
        let messageContentNS = NSString(string:" : " + messageContent + "\n")

        let highlightedMessage = NSMutableAttributedString(string: messageContentNS as String)

        if let highlightTerm = highlightTerm {
            let rangeOfSearchedTerm = messageContentNS.rangeOfString(highlightTerm)
            highlightedMessage.addAttribute(NSForegroundColorAttributeName, value: NSColor.redColor(), range: rangeOfSearchedTerm)
        }

        result.appendAttributedString(highlightedMessage)
        
        return result
        
    }

    func formatMessageDate(messageDate:NSDate) -> NSAttributedString
    {
        return NSMutableAttributedString(string: fullDateFormatter.stringFromDate(messageDate) + "\n")
    }
    
    func colorForMessageService(serviceName:String) -> NSColor?
    {
        var color:NSColor?
        
        switch serviceName {
        case "iMessage": color = NSColor.blueColor()
        case "SMS" : color = NSColor.greenColor()
        case "jabber": color = NSColor.orangeColor()
        default: color = nil
        }
        
        return color
    }

}
