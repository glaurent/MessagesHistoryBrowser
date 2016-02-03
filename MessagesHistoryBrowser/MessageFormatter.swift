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

    var detailedSender = false

    let dateParagraphStyle = NSMutableParagraphStyle()
    let contactNameParagraphStyle = NSMutableParagraphStyle()

    let meColor = NSColor.clearColor()
    let contactColor = NSColor(red: 0x66 / 255.0, green: 0x66 / 255.0, blue: 0xff / 255.0, alpha: 1.0)
    let searchHighlightColor = NSColor.redColor()

    init() {
        dateFormatter.timeStyle = .ShortStyle
        dateFormatter.dateStyle = .NoStyle
        
        fullDateFormatter.timeStyle = .LongStyle
        fullDateFormatter.dateStyle = .LongStyle

        terseTimeMode = true

        dateParagraphStyle.alignment = .Center
//        dateParagraphStyle.lineSpacing = 15
        dateParagraphStyle.paragraphSpacing = 15
        dateParagraphStyle.paragraphSpacingBefore = 15

        contactNameParagraphStyle.alignment = .Center
//        contactNameParagraphStyle.lineSpacing = 15
        contactNameParagraphStyle.paragraphSpacing = 25
        contactNameParagraphStyle.paragraphSpacingBefore = 25

    }

    // used for log saves
    //
    func formatMessageAsString(message:ChatMessage) -> String
    {
        let messageContent = message.content ?? noMessageString
        let sender = message.isFromMe ? meString : message.chat.contact.name
        let dateString = dateFormatter.stringFromDate(message.date)

        let messageContentAndSender = "\(dateString) - \(sender) : \(messageContent)"

        return messageContentAndSender
    }


    func formatMessage(message:ChatMessage, withHighlightTerm highlightTerm:String? = nil) -> NSAttributedString?
    {
        guard let messageContent = message.content else { return nil }
        guard messageContent != "" else { return nil }

        let result = formatMessagePreamble(message, detailed: detailedSender)

        // highlight message content
        //
        let messageContentNS = NSString(string:" : " + messageContent + "\n") // has to be an NSString because we use rangeOfString below

        let highlightedMessage = NSMutableAttributedString(string: messageContentNS as String)

        if let highlightTerm = highlightTerm {
            let rangeOfSearchedTerm = messageContentNS.rangeOfString(highlightTerm)
            highlightedMessage.addAttribute(NSForegroundColorAttributeName, value: searchHighlightColor, range: rangeOfSearchedTerm)
        }

        result.appendAttributedString(highlightedMessage)
        
        return result
        
    }

    func formatMessagePreamble(message:ChatMessage, detailed:Bool) -> NSMutableAttributedString
    {
        let dateString = NSMutableAttributedString(string: dateFormatter.stringFromDate(message.date))

        if detailed {

            let chatContact = message.contact

            let sender:NSMutableAttributedString

            if message.isFromMe {
                sender = NSMutableAttributedString(string: meString, attributes: [NSBackgroundColorAttributeName : meColor])
            } else {
                sender = NSMutableAttributedString(string: chatContact.name , attributes: [NSBackgroundColorAttributeName : contactColor])
            }

            let dateString = NSMutableAttributedString(string: dateFormatter.stringFromDate(message.date))
            dateString.appendAttributedString(NSAttributedString(string: " - "))
            dateString.appendAttributedString(sender)

            return dateString

        } else {

            let range = NSRange(location: 0, length: dateString.length)

            if message.isFromMe {
                dateString.addAttribute(NSBackgroundColorAttributeName, value: meColor, range: range)
            } else {
                dateString.addAttribute(NSBackgroundColorAttributeName, value: contactColor, range: range)
            }
            
            return dateString
        }
    }

    func formatMessageDate(messageDate:NSDate) -> NSAttributedString
    {
        let res = NSMutableAttributedString(string: fullDateFormatter.stringFromDate(messageDate) + "\n")

        let range = NSRange(location: 0, length: res.length)

//        res.addAttribute(NSParagraphStyleAttributeName, value: dateParagraphStyle, range: range)
//        res.addAttribute(NSForegroundColorAttributeName, value: NSColor.lightGrayColor(), range: range)

        res.addAttributes([
            NSParagraphStyleAttributeName  : dateParagraphStyle,
            NSForegroundColorAttributeName : NSColor.lightGrayColor()],
            range: range)

        return res
    }

    func formatMessageContact(messageContact:ChatContact) -> NSAttributedString
    {
        let res = NSMutableAttributedString(string: messageContact.name + "\n")

        let range = NSRange(location: 0, length: res.length)

        res.addAttributes([
            NSParagraphStyleAttributeName  : contactNameParagraphStyle,
            NSForegroundColorAttributeName : NSColor.darkGrayColor()],
            range: range)
        
        return res
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
