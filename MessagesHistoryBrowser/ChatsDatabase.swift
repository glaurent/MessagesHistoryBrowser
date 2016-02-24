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

//    let chatsDBPath = "/Users/glaurent/tmp/chat.db"

    let chatsDBPath = NSString(string:"~/Library/Messages/chat.db").stringByStandardizingPath

    var contactsPhoneNumber:ContactsMap! // want delayed init

    var allChats:[Chat] {
        get {
            return Chat.allChatsInContext(MOCController.sharedInstance.managedObjectContext)
        }
    }

    var db:Connection!

//    let progress:NSProgress

//    lazy var moc = MOCController.sharedInstance.managedObjectContext

    override init() {

        contactsPhoneNumber = ContactsMap.sharedInstance

        do {

            db = try Connection(chatsDBPath, readonly:true)

            super.init()

        } catch {
            super.init()
            NSLog("%@ error", __FUNCTION__)
        }

    }


    func populate(progress:NSProgress, completion:() -> Void)
    {
        progress.becomeCurrentWithPendingUnitCount(1) // ContactsMap populate take little time

        self.contactsPhoneNumber.populate()

        progress.resignCurrent()

        let workerContext = MOCController.sharedInstance.workerContext()

        workerContext.performBlock({ () -> Void in

            if Chat.numberOfChatsInContext(workerContext) == 0 {

                progress.becomeCurrentWithPendingUnitCount(3)
                self.importAllChatsFromDB(workerContext) // has its own NSProgress
                progress.resignCurrent()

                progress.becomeCurrentWithPendingUnitCount(6)
                self.collectAllMessagesFromAllChats(workerContext) // same
                progress.resignCurrent()
            }

            do {
                try workerContext.save()
                MOCController.sharedInstance.save()
            } catch let error as NSError {
                print("ChatsDatabase.populate : worker context save fail : \(error)")
            }

            // run completion block on main queue
            //
            dispatch_async(dispatch_get_main_queue(), { () -> Void in

                completion()

            })

        })

    }

    func importAllChatsFromDB(localContext:NSManagedObjectContext)
    {
        let taskProgress = NSProgress(totalUnitCount: -1)

        dispatch_async(dispatch_get_main_queue()) { taskProgress.localizedDescription = NSLocalizedString("Importing chats...", comment: "") }

        let chats = Table("chat")
        
        let chatRowIDColumn = Expression<Int>("ROWID")
        let chatGUIDColumn = Expression<String>("guid")
        let serviceNameColumn = Expression<String>("service_name")
        let chatIdentifierColumn = Expression<String>("chat_identifier")
        
        // Iterate over all chats
        //

        let nbRows = Int64(db.scalar(chats.count))
        taskProgress.totalUnitCount = nbRows

        var rowIndex:Int64 = 0

        let dbRows = db.prepare(chats.select(chatRowIDColumn, chatGUIDColumn, serviceNameColumn, chatIdentifierColumn))

        for chatData in dbRows {
            
            let guid = chatData[chatGUIDColumn]
            let rowID = chatData[chatRowIDColumn]
            let identifier = chatData[chatIdentifierColumn]
            let serviceName = chatData[serviceNameColumn]
            
            let chatContact = contactForIdentifier(identifier, service:serviceName, inContext: localContext)
            
            let _ = Chat(managedObjectContext:localContext, withContact:chatContact, withServiceName:serviceName,  withGUID: guid, andRowID: rowID)
            
            NSLog("chat : %@ \tcontact : %@\trowId: %d", guid, chatContact.name, rowID)

            dispatch_async(dispatch_get_main_queue()) { taskProgress.completedUnitCount = rowIndex }
            

            rowIndex += 1
        }

        MOCController.sharedInstance.save()

    }


    func contactForIdentifier(identifier:String, service serviceName:String, inContext context:NSManagedObjectContext) -> ChatContact
    {
        var contactName = identifier
        var contactIsKnown = false
        var contactCNIdentifier = ""

        if serviceName == "AIM" || serviceName == "Jabber" {

            if let chatContactNameIdentifierPair = contactsPhoneNumber.nameForInstantMessageAddress(identifier) {
                contactName = chatContactNameIdentifierPair.0
                contactCNIdentifier = chatContactNameIdentifierPair.1
                contactIsKnown = true
            } else {
                contactIsKnown = false
                NSLog("\(__FUNCTION__) : no contact name found for identifier \(identifier)")
            }

        } else if serviceName == "iMessage" || serviceName == "SMS" {

            // check if identifier contains a '@'
            if identifier.characters.contains("@") {
                if let chatContactNameIdentifierPair = contactsPhoneNumber.nameForEmailAddress(identifier) {
                    contactName = chatContactNameIdentifierPair.0
                    contactCNIdentifier = chatContactNameIdentifierPair.1
                    contactIsKnown = true
                }
            } else if let chatContactNameIdentifierPair = contactsPhoneNumber.nameForPhoneNumber(identifier) {
                contactName = chatContactNameIdentifierPair.0
                contactCNIdentifier = chatContactNameIdentifierPair.1
                contactIsKnown = true
            } else {
                contactName = identifier
                contactIsKnown = false
            }
        } else {
            contactName = identifier
            contactIsKnown = false
        }

        let contact = ChatContact.contactIn(context, named: contactName, withIdentifier: contactCNIdentifier)
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

    func collectMessagesForChat(chat:Chat)
    {
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

            let chatMessage = ChatMessage(managedObjectContext: chat.managedObjectContext!, withMessage: messageContent, withDate: messageDate, inChat: chat)
            chatMessage.isFromMe = messageData[isFromMeColumn]
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

            let _ = ChatAttachment(managedObjectContext: chat.managedObjectContext!, withFileName: attachmentFileName, withDate: attachmentDate, inChat:chat)
        }

    }

    func collectAllMessagesFromAllChats(localContext:NSManagedObjectContext)
    {
        let allContacts = ChatContact.allContactsInContext(localContext)
        let allContactsCount = Int64(allContacts.count)

        let taskProgress = NSProgress(totalUnitCount: allContactsCount)
        dispatch_async(dispatch_get_main_queue()) { taskProgress.localizedDescription = NSLocalizedString("Importing chat messages...", comment: "") }

        for contact in allContacts {
            for obj in contact.chats {
                let chat = obj as! Chat
                if chat.messages.count == 0 {
                    collectMessagesForChat(chat)
                }
            }

            indexMessagesForContact(contact)

            dispatch_async(dispatch_get_main_queue()) { taskProgress.completedUnitCount += 1 }
            
        }
    }

    // TODO : this method is probably no longer useful as the whole messages DB is imported at startup anyway
    //
    func collectMessagesForContact(contact:ChatContact)
    {
        var newMessagesCollected = false

        for c in contact.chats {
            let chat = c as! Chat
            if chat.messages.count == 0 {
                collectMessagesForChat(chat)
                newMessagesCollected = true
            }
        }

        if newMessagesCollected {
            indexMessagesForContact(contact)
        }
    }

    func indexMessagesForContact(contact:ChatContact)
    {
        let allMessages = contact.messages.allObjects as! [ChatMessage]

        let allMessagesDateSorted = allMessages.sort { $0.date.compare($1.date) == .OrderedAscending }

        var index:Int64 = 0

        _ = allMessagesDateSorted.map { $0.index = index; index += 1 }

    }

    // MARK: String Search


}
