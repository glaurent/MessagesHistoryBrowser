//
//  ChatsDatabase.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 04/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import SQLite

class ChatsDatabase: NSObject {

    static let sharedInstance = ChatsDatabase()

    let chatsDBPath = "/Users/glaurent/tmp/chat.db"

    var contactsPhoneNumber:ContactsMap! // want delayed init

    var allChats:[Chat] {
        get {
            return Chat.allChatsInContext(moc)
        }
    }

    var db:Connection!

    lazy var moc = (NSApp.delegate as! AppDelegate).managedObjectContext

    override init() {

        do {

//            let appDelegate = NSApp.delegate as! AppDelegate
//
//            appDelegate.clearAllCoreData()

            contactsPhoneNumber = ContactsMap.sharedInstance

            db = try Connection(chatsDBPath, readonly:true)

            super.init()

            if Chat.allChatsInContext(moc).count == 0 {
                importAllChatsFromDB()
            }

        } catch {
            super.init()
            NSLog("%@ error", __FUNCTION__)
        }

    }

    func importAllChatsFromDB()
    {
        let chats = Table("chat")
        
        let chatRowIDColumn = Expression<Int>("ROWID")
        let chatGUIDColumn = Expression<String>("guid")
        let serviceNameColumn = Expression<String>("service_name")
        let chatIdentifierColumn = Expression<String>("chat_identifier")
        
        // Iterate over all chats
        //
        for chatData in db.prepare(chats.select(chatRowIDColumn, chatGUIDColumn, serviceNameColumn, chatIdentifierColumn)) {
            
            let guid = chatData[chatGUIDColumn]
            let rowID = chatData[chatRowIDColumn]
            let identifier = chatData[chatIdentifierColumn]
            let serviceName = chatData[serviceNameColumn]
            
            let chatContact = contactForIdentifier(identifier, service:serviceName)
            
            let _ = Chat(managedObjectContext:moc, withContact:chatContact, withGUID: guid, andRowID: rowID)
            
            NSLog("chat : %@ \tcontact : %@\trowId: %d", guid, chatContact.name, rowID)
            
        }
        
        do { try moc.save() } catch {}

    }


    func contactForIdentifier(identifier:String, service serviceName:String) -> ChatContact
    {
        var contactName = identifier
        var contactIsKnown = false

        if serviceName == "AIM" || serviceName == "Jabber" {

            if let chatContactName = contactsPhoneNumber.nameForInstantMessageAddress(identifier) {
                contactName = chatContactName
                contactIsKnown = true
            } else {
                contactIsKnown = false
                NSLog("\(__FUNCTION__) : no contact name found for identifier \(identifier)")
            }

        } else if serviceName == "iMessage" || serviceName == "SMS" {

            // check if identifier contains a '@'
            if identifier.characters.contains("@") {
                if let chatContactName = contactsPhoneNumber.nameForEmailAddress(identifier) {
                    contactName = chatContactName
                    contactIsKnown = true
                }
            } else if let chatContactName = contactsPhoneNumber.nameForPhoneNumber(identifier) {
                contactName = chatContactName
                contactIsKnown = true
            } else {
                contactName = identifier
                contactIsKnown = false
            }
        } else {
            contactName = identifier
            contactIsKnown = false
        }

        let contact = ChatContact.contactIn(moc, named: contactName)
        contact.known = contactIsKnown
        return contact
    }

    func messagesForChat(chat:Chat) -> ([ChatMessage], [ChatAttachment])
    {
        if chat.messages.count == 0 {
            collectMessagesForChat(chat)
        }

        let allMessages = chat.messages.allObjects as! [ChatMessage]

        let allMessagesSorted = allMessages.sort { $0.date.compare($1.date) == .OrderedAscending }

        let allAttachments = chat.attachments.allObjects as! [ChatAttachment]
        let allAttachmentsSorted = allAttachments.sort { $0.date.compare($1.date) == .OrderedAscending }

        return (allMessagesSorted, allAttachmentsSorted)
    
    }

    func collectMessagesForChat(chat:Chat) -> [ChatMessage]
    {
        var res:[ChatMessage] = []

        let messagesTable  = Table("message")
        let isFromMeColumn = Expression<Bool>("is_from_me")
        let textColumn     = Expression<String?>("text")
        let dateColumn     = Expression<Int>("date")

        let chatHandleJoinTable = Table("chat_handle_join")
        let handleIdColumn      = Expression<Int>("handle_id")
        let chatIdColumn        = Expression<Int>("chat_id")

        let chatTable   = Table("chat")
        let rowIDColumn = Expression<Int>("ROWID")
        let guidColumn  = Expression<String>("guid")

        let chatIDQuery = db.prepare(chatTable.select(rowIDColumn).filter(guidColumn == chat.guid))
        var allRowIDs = [Int]()
        for row in chatIDQuery {
            allRowIDs.append(row[rowIDColumn])
        }


        let handleIDQuery = db.prepare(chatHandleJoinTable.select(handleIdColumn).filter(allRowIDs.contains(chatIdColumn)))
        var allHandleIDs = [Int]()
        for row in handleIDQuery {
            allHandleIDs.append(row[handleIdColumn])
        }

        let query = db.prepare(messagesTable.select(isFromMeColumn, textColumn, dateColumn).filter(allHandleIDs.contains(handleIdColumn)))

        for messageData in query {
            let messageContent = messageData[textColumn] ?? ""
            let dateInt = messageData[dateColumn]
            let dateTimeInterval = NSTimeInterval(dateInt)
            let messageDate = NSDate(timeIntervalSinceReferenceDate: dateTimeInterval)
//            NSLog("message : \(messageContent)")
            let chatMessage = ChatMessage(managedObjectContext: moc, withMessage: messageContent, withDate: messageDate, inChat: chat)
            chatMessage.isFromMe = messageData[isFromMeColumn]
            res.append(chatMessage)
        }


        // attachments
        //
        let attachments = Table("attachment")
        let filenameColumn = Expression<String>("filename")
        let attachmentIdColumn = Expression<Int>("attachment_id")
        let cacheHasAttachmentColumn = Expression<Bool>("cache_has_attachments")

        let messagesWithAttachmentsROWIDsQuery = db.prepare(messagesTable.select(rowIDColumn, cacheHasAttachmentColumn, handleIdColumn).filter(allHandleIDs.contains(handleIdColumn) && cacheHasAttachmentColumn == true))

        var messagesWithAttachmentsROWIDs = [Int]()
        for row in messagesWithAttachmentsROWIDsQuery {
            messagesWithAttachmentsROWIDs.append(row[rowIDColumn])
        }

        let messageAttachmentJoinTable = Table("message_attachment_join")
        let messageIDColumn = Expression<Int>("message_id")
        let attachmentIDsQuery = db.prepare(messageAttachmentJoinTable.select(messageIDColumn, attachmentIdColumn).filter(messagesWithAttachmentsROWIDs.contains(messageIDColumn)))

        var allAttachmentIDs = [Int]()
        for row in attachmentIDsQuery {
            allAttachmentIDs.append(row[attachmentIdColumn])
        }


        let attachmentDateColumn = Expression<Int>("created_date")

        let attachmentDataQuery = db.prepare(attachments.select(rowIDColumn, filenameColumn, attachmentDateColumn).filter(allAttachmentIDs.contains(rowIDColumn)))

        for attachmentData in attachmentDataQuery {
            let attachmentFileName = attachmentData[filenameColumn]
            let attachmentDateInt = attachmentData[attachmentDateColumn]
            let attachmentTimeInterval = NSTimeInterval(attachmentDateInt)
            let attachmentDate = NSDate(timeIntervalSinceReferenceDate: attachmentTimeInterval)

            let _ = ChatAttachment(managedObjectContext: moc, withFileName: attachmentFileName, withDate: attachmentDate, inChat:chat)
        }

        return res
    }

    func collectAllMessagesFromAllChats()
    {
        for contact in ChatContact.allContactsInContext(moc) {
            for obj in contact.chats {
                let chat = obj as! Chat
                if chat.messages.count == 0 {
                    messagesForChat(chat)
                }
            }
        }
    }

    func collectMessagesForContact(contact:ChatContact)
    {
        for c in contact.chats {
            let chat = c as! Chat
            if chat.messages.count == 0 {
                collectMessagesForChat(chat)
            }
        }
    }

    func searchChatsForString(string:String, afterDate:NSDate? = nil, beforeDate:NSDate? = nil) -> [ChatMessage]
    {
        var result = [ChatMessage]()

        let fetchRequest = NSFetchRequest(entityName: ChatMessage.EntityName)
        let argArray:[AnyObject] = [ChatMessage.Attributes.content.rawValue, string]


        let stringSearchPredicate = NSPredicate(format: "%K CONTAINS %@", argumentArray:argArray)

//        if let afterDate = afterDate {
//
//        }
        fetchRequest.predicate = stringSearchPredicate
        do {
            let matchingMessages = try moc.executeFetchRequest(fetchRequest)
            result = matchingMessages as! [ChatMessage]
        } catch let error as NSError {
            print("\(__FUNCTION__) : Could not fetch \(error), \(error.userInfo)")
        }

        return result
    }

}
