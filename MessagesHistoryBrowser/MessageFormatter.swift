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

    var ShowTerseTime:Bool = true {
        didSet {
            dateFormatter.dateStyle = ShowTerseTime ? .none : .short
        }
    }

    var showDetailedSender = false

    let dateParagraphStyle = NSMutableParagraphStyle()
    let contactNameParagraphStyle = NSMutableParagraphStyle()
    let separatorParagraphStyle = NSMutableParagraphStyle()

    let meColor = NSColor.clear
    let contactColor = NSColor(calibratedRed: 0.231, green: 0.518, blue: 0.941, alpha: 1) // NSColor(red: 0x66 / 255.0, green: 0x66 / 255.0, blue: 0xff / 255.0, alpha: 1.0)
    let searchHighlightColor = NSColor(calibratedRed: 0.951, green: 0.165, blue: 0.276, alpha: 1) // NSColor.red

    init() {
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .none
        
        fullDateFormatter.timeStyle = .long
        fullDateFormatter.dateStyle = .long

//        ShowTerseTime = true

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

        let result = formatMessagePreamble(message, detailed: showDetailedSender)

        // highlight message content
        //
//        let messageContentNS = NSString(string:" - \(message.index) : " + messageContent + "\n") // has to be an NSString because we use rangeOfString below
        let messageContentNS = NSString(string:" : " + messageContent + "\n") // has to be an NSString because we use rangeOfString below

        let highlightedMessage = NSMutableAttributedString(string: messageContentNS as String, attributes: [NSAttributedString.Key.foregroundColor : NSColor.textColor])

        if let highlightTerm = highlightTerm {
            let rangeOfSearchedTerm = messageContentNS.range(of: highlightTerm)
            highlightedMessage.addAttribute(NSAttributedString.Key.foregroundColor, value: searchHighlightColor, range: rangeOfSearchedTerm)
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
                sender = NSMutableAttributedString(string: meString, attributes: [NSAttributedString.Key.foregroundColor : NSColor.textColor,
                    NSAttributedString.Key.backgroundColor : meColor])
            } else {
                sender = NSMutableAttributedString(string: chatContact.name , attributes: [NSAttributedString.Key.foregroundColor : NSColor.textColor,
                                                                                           NSAttributedString.Key.backgroundColor : contactColor])
            }

            let dateString = NSMutableAttributedString(string: dateFormatter.string(from: message.date as Date), attributes:[NSAttributedString.Key.foregroundColor : NSColor.textColor])
            dateString.append(NSAttributedString(string: " - "))
//            dateString.appendAttributedString(NSAttributedString(string: " - \(message.index) -"))

            dateString.append(sender)

            return dateString

        } else {

            let range = NSRange(location: 0, length: dateString.length)

            if message.isFromMe {
                dateString.addAttribute(NSAttributedString.Key.backgroundColor, value: meColor, range: range)
            } else {
                dateString.addAttribute(NSAttributedString.Key.backgroundColor, value: contactColor, range: range)
            }
            dateString.addAttribute(NSAttributedString.Key.foregroundColor, value: NSColor.textColor, range: range)
            
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
            NSAttributedString.Key.paragraphStyle  : dateParagraphStyle,
            NSAttributedString.Key.foregroundColor : NSColor.lightGray],
            range: range)

        return res
    }

    func formatMessageContact(_ messageContact:ChatContact) -> NSAttributedString
    {
        let res = NSMutableAttributedString(string: messageContact.name + "\n")

        let range = NSRange(location: 0, length: res.length)

        res.addAttributes([
            NSAttributedString.Key.font : NSFont.boldSystemFont(ofSize: 13.0),
            NSAttributedString.Key.paragraphStyle  : contactNameParagraphStyle,
            NSAttributedString.Key.foregroundColor : NSColor.darkGray],
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
            NSAttributedString.Key.font : NSFont.systemFont(ofSize: 15.0),
            NSAttributedString.Key.paragraphStyle  : separatorParagraphStyle,
            NSAttributedString.Key.foregroundColor : NSColor.lightGray],
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
