//
//  MessageFormatter.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 18/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class MessageFormatter {

    let dateFormatter = DateFormatter()
    let fullDateFormatter = DateFormatter()
    
    let noMessageString = "<no message>"
    let meString = "me"
    let unknownContact = "<unknown>"

    var terseTimeMode:Bool {
        didSet {
            dateFormatter.dateStyle = terseTimeMode ? .none : .short
        }
    }

    var detailedSender = false

    let dateParagraphStyle = NSMutableParagraphStyle()
    let contactNameParagraphStyle = NSMutableParagraphStyle()
    let separatorParagraphStyle = NSMutableParagraphStyle()

    let meColor = NSColor.clear
    let contactColor = NSColor(red: 0x66 / 255.0, green: 0x66 / 255.0, blue: 0xff / 255.0, alpha: 1.0)
    let searchHighlightColor = NSColor.red

    init() {
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .none
        
        fullDateFormatter.timeStyle = .long
        fullDateFormatter.dateStyle = .long

        terseTimeMode = true

        dateParagraphStyle.alignment = .center
//        dateParagraphStyle.lineSpacing = 15
        dateParagraphStyle.paragraphSpacing = 15
        dateParagraphStyle.paragraphSpacingBefore = 15

        contactNameParagraphStyle.alignment = .center
//        contactNameParagraphStyle.lineSpacing = 15
        contactNameParagraphStyle.paragraphSpacing = 25
        contactNameParagraphStyle.paragraphSpacingBefore = 25

    }

    // used for log saves
    //
    func formatMessageAsString(_ message:ChatMessage) -> String
    {
        let messageContent = message.content ?? noMessageString
        let sender = message.isFromMe ? meString : message.chat.contact.name
        let dateString = dateFormatter.string(from: message.date as Date)

        let messageContentAndSender = "\(dateString) - \(sender) : \(messageContent)"

        return messageContentAndSender
    }


    func formatMessage(_ message:ChatMessage, withHighlightTerm highlightTerm:String? = nil) -> NSAttributedString?
    {
        guard let messageContent = message.content else { return nil }
        guard messageContent != "" else { return nil }

        let result = formatMessagePreamble(message, detailed: detailedSender)

        // highlight message content
        //
//        let messageContentNS = NSString(string:" - \(message.index) : " + messageContent + "\n") // has to be an NSString because we use rangeOfString below
        let messageContentNS = NSString(string:" : " + messageContent + "\n") // has to be an NSString because we use rangeOfString below

        let highlightedMessage = NSMutableAttributedString(string: messageContentNS as String)

        if let highlightTerm = highlightTerm {
            let rangeOfSearchedTerm = messageContentNS.range(of: highlightTerm)
            highlightedMessage.addAttribute(NSAttributedStringKey.foregroundColor, value: searchHighlightColor, range: rangeOfSearchedTerm)
        }

        result.append(highlightedMessage)
        
        return result
        
    }

    func formatMessagePreamble(_ message:ChatMessage, detailed:Bool) -> NSMutableAttributedString
    {
        let dateString = NSMutableAttributedString(string: dateFormatter.string(from: message.date as Date))

        if detailed {

            let chatContact = message.contact

            let sender:NSMutableAttributedString

            if message.isFromMe {
                sender = NSMutableAttributedString(string: meString, attributes: [NSAttributedStringKey.backgroundColor : meColor])
            } else {
                sender = NSMutableAttributedString(string: chatContact.name , attributes: [NSAttributedStringKey.backgroundColor : contactColor])
            }

            let dateString = NSMutableAttributedString(string: dateFormatter.string(from: message.date as Date))
            dateString.append(NSAttributedString(string: " - "))
//            dateString.appendAttributedString(NSAttributedString(string: " - \(message.index) -"))

            dateString.append(sender)

            return dateString

        } else {

            let range = NSRange(location: 0, length: dateString.length)

            if message.isFromMe {
                dateString.addAttribute(NSAttributedStringKey.backgroundColor, value: meColor, range: range)
            } else {
                dateString.addAttribute(NSAttributedStringKey.backgroundColor, value: contactColor, range: range)
            }
            
            return dateString
        }
    }

    func formatMessageDate(_ messageDate:Date) -> NSAttributedString
    {
        let res = NSMutableAttributedString(string: fullDateFormatter.string(from: messageDate) + "\n")

        let range = NSRange(location: 0, length: res.length)

//        res.addAttribute(NSParagraphStyleAttributeName, value: dateParagraphStyle, range: range)
//        res.addAttribute(NSForegroundColorAttributeName, value: NSColor.lightGrayColor(), range: range)

        res.addAttributes([
            NSAttributedStringKey.paragraphStyle  : dateParagraphStyle,
            NSAttributedStringKey.foregroundColor : NSColor.lightGray],
            range: range)

        return res
    }

    func formatMessageContact(_ messageContact:ChatContact) -> NSAttributedString
    {
        let res = NSMutableAttributedString(string: messageContact.name + "\n")

        let range = NSRange(location: 0, length: res.length)

        res.addAttributes([
            NSAttributedStringKey.font : NSFont.boldSystemFont(ofSize: 13.0),
            NSAttributedStringKey.paragraphStyle  : contactNameParagraphStyle,
            NSAttributedStringKey.foregroundColor : NSColor.darkGray],
            range: range)
        
        return res
    }

    let separatorString:NSAttributedString = {
        let separatorParagraphStyle = NSMutableParagraphStyle()
        separatorParagraphStyle.alignment = .center
        separatorParagraphStyle.paragraphSpacing = 10
        separatorParagraphStyle.paragraphSpacingBefore = 5

        let res = NSMutableAttributedString(string: "_____\n")

        let range = NSRange(location: 0, length: res.length)

        res.addAttributes([
            NSAttributedStringKey.font : NSFont.systemFont(ofSize: 15.0),
            NSAttributedStringKey.paragraphStyle  : separatorParagraphStyle,
            NSAttributedStringKey.foregroundColor : NSColor.lightGray],
            range: range)

        return res

    }()

    func colorForMessageService(_ serviceName:String) -> NSColor?
    {
        var color:NSColor?
        
        switch serviceName {
        case "iMessage": color = NSColor.blue
        case "SMS" : color = NSColor.green
        case "jabber": color = NSColor.orange
        default: color = nil
        }
        
        return color
    }

}
