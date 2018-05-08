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

    let chatsDBPath = NSString(string:"~/Library/Messages/chat.db").standardizingPath

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
            NSLog("%@ error", #function)
        }

    }


    func populate(_ progress:Progress, completion:@escaping () -> Void)
    {
        contactsPhoneNumber.populate()

        let workerContext = MOCController.sharedInstance.workerContext()

        workerContext.perform({ () -> Void in

            if Chat.numberOfChatsInContext(workerContext) == 0 {

                progress.localizedDescription = NSLocalizedString("Importing chats...", comment: "")
                progress.becomeCurrent(withPendingUnitCount: 4)
                self.importAllChatsFromDB(workerContext)
                progress.resignCurrent()

                progress.localizedDescription = NSLocalizedString("Importing chat messages...", comment: "")
                progress.becomeCurrent(withPendingUnitCount: 6)
                self.collectAllMessagesFromAllChats(workerContext)
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
            DispatchQueue.main.async(execute: { () -> Void in

                completion()

            })

        })

    }

    func importAllChatsFromDB(_ localContext:NSManagedObjectContext)
    {
        let taskProgress = Progress(totalUnitCount: -1)

        let chats = Table("chat")
        
        let chatRowIDColumn = Expression<Int>("ROWID")
        let chatGUIDColumn = Expression<String>("guid")
        let serviceNameColumn = Expression<String>("service_name")
        let chatIdentifierColumn = Expression<String>("chat_identifier")
        
        // Iterate over all chats
        //

        do {

            let nbRows = try Int64(db.scalar(chats.count))
            taskProgress.totalUnitCount = nbRows

            var rowIndex:Int64 = 0


            let dbRows = try db.prepare(chats.select(chatRowIDColumn, chatGUIDColumn, serviceNameColumn, chatIdentifierColumn))

            for chatData in dbRows {

                let guid = chatData[chatGUIDColumn]
                let rowID = chatData[chatRowIDColumn]
                let identifier = chatData[chatIdentifierColumn]
                let serviceName = chatData[serviceNameColumn]

                let chatContact = contactForIdentifier(identifier, service:serviceName, inContext: localContext)

                let _ = Chat(managedObjectContext:localContext, withContact:chatContact, withServiceName:serviceName,  withGUID: guid, andRowID: rowID)
            
//            NSLog("chat : %@ \tcontact : %@\trowId: %d", guid, chatContact.name, rowID)

            DispatchQueue.main.async { taskProgress.completedUnitCount = rowIndex }

            rowIndex += 1
        }

        MOCController.sharedInstance.save()

        } catch {
            NSLog("\(#function) : error when preparing DB select")
        }
    }


    func contactForIdentifier(_ identifier:String, service serviceName:String, inContext context:NSManagedObjectContext) -> ChatContact
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
                NSLog("\(#function) : no contact name found for identifier \(identifier)")
            }

        } else if serviceName == "iMessage" || serviceName == "SMS" {

            // check if identifier contains a '@'
            if identifier.contains("@") {
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

    func messagesForChat(_ chat:Chat) -> ([ChatMessage], [ChatAttachment])
    {
        if chat.messages.count == 0 {
            collectMessagesForChat(chat)
        }

        let allMessages = chat.messages.allObjects as! [ChatMessage]

        let allMessagesSorted = allMessages.sorted { $0.date.compare($1.date as Date) == .orderedAscending }

        let allAttachments = chat.attachments.allObjects as! [ChatAttachment]
        let allAttachmentsSorted = allAttachments.sorted { $0.date.compare($1.date as Date) == .orderedAscending }

        return (allMessagesSorted, allAttachmentsSorted)
    
    }

    func collectMessagesForChat(_ chat:Chat)
    {
        do {
            let messagesTable  = Table("message")
            let isFromMeColumn = Expression<Bool>("is_from_me")
            let textColumn     = Expression<String?>("text")
            let dateColumn     = Expression<Int>("date")

//            let dateDeliveredColumn = Expression<Int>("date_delivered") // used only for sanity check on dateColumn value

            let chatHandleJoinTable = Table("chat_handle_join")
            let handleIdColumn      = Expression<Int>("handle_id")
            let chatIdColumn        = Expression<Int>("chat_id")

            let chatTable   = Table("chat")
            let rowIDColumn = Expression<Int>("ROWID")
            let guidColumn  = Expression<String>("guid")

            let chatIDQuery = try db.prepare(chatTable.select(rowIDColumn).filter(guidColumn == chat.guid))
            var allRowIDs = [Int]()
            for row in chatIDQuery {
                allRowIDs.append(row[rowIDColumn])
            }


            let handleIDQuery = try db.prepare(chatHandleJoinTable.select(handleIdColumn).filter(allRowIDs.contains(chatIdColumn)))
            var allHandleIDs = [Int]()
            for row in handleIDQuery {
                allHandleIDs.append(row[handleIdColumn])
            }

            let query = try db.prepare(messagesTable.select(isFromMeColumn, textColumn, dateColumn).filter(allHandleIDs.contains(handleIdColumn)))

            for messageData in query {
                let messageContent = messageData[textColumn] ?? ""
                var dateInt = messageData[dateColumn]
                if dateInt > Int(10e9) { // I have this case of timestamp values being multiplied by 10e8 on my iMac running High Sierra, with no apparent effect on the values displayed in the chats history
                    dateInt = dateInt / Int(10e8)
                }
                let dateTimeInterval = TimeInterval(dateInt)
                let messageDate = Date(timeIntervalSinceReferenceDate: dateTimeInterval)
//              NSLog("message : \(messageContent)")

                let chatMessage = ChatMessage(managedObjectContext: chat.managedObjectContext!, withMessage: messageContent, withDate: messageDate, inChat: chat)
                chatMessage.isFromMe = messageData[isFromMeColumn]
            }


            // attachments
            //
            let attachments = Table("attachment")
            let filenameColumn = Expression<String?>("filename")
            let attachmentIdColumn = Expression<Int>("attachment_id")
            let cacheHasAttachmentColumn = Expression<Bool>("cache_has_attachments")

            let messagesWithAttachmentsROWIDsQuery = try db.prepare(messagesTable.select(rowIDColumn, cacheHasAttachmentColumn, handleIdColumn).filter(allHandleIDs.contains(handleIdColumn) && cacheHasAttachmentColumn == true))

            var messagesWithAttachmentsROWIDs = [Int]()
            for row in messagesWithAttachmentsROWIDsQuery {
                messagesWithAttachmentsROWIDs.append(row[rowIDColumn])
            }

            let messageAttachmentJoinTable = Table("message_attachment_join")
            let messageIDColumn = Expression<Int>("message_id")
            let attachmentIDsQuery = try db.prepare(messageAttachmentJoinTable.select(messageIDColumn, attachmentIdColumn).filter(messagesWithAttachmentsROWIDs.contains(messageIDColumn)))

            var allAttachmentIDs = [Int]()
            for row in attachmentIDsQuery {
                allAttachmentIDs.append(row[attachmentIdColumn])
            }


            let attachmentDateColumn = Expression<Int>("created_date")

            let attachmentDataQuery = try db.prepare(attachments.select(rowIDColumn, filenameColumn, attachmentDateColumn).filter(allAttachmentIDs.contains(rowIDColumn)))

            for attachmentData in attachmentDataQuery {
                let attachmentFileName:String? = attachmentData[filenameColumn]
                let attachmentDateInt = attachmentData[attachmentDateColumn]
                let attachmentTimeInterval = TimeInterval(attachmentDateInt)
                let attachmentDate = Date(timeIntervalSinceReferenceDate: attachmentTimeInterval)

                if let attachmentFileName = attachmentFileName {
                    let _ = ChatAttachment(managedObjectContext: chat.managedObjectContext!, withFileName: attachmentFileName, withDate: attachmentDate as Date, inChat:chat)
                }
            }
            
        } catch {
            NSLog("\(#function) : error when preparing DB select")
        }

    }

    func collectAllMessagesFromAllChats(_ localContext:NSManagedObjectContext)
    {
        let allContacts = ChatContact.allContactsInContext(localContext)
        let allContactsCount = Int64(allContacts.count)

        let taskProgress = Progress(totalUnitCount: allContactsCount)

        for contact in allContacts {
            for obj in contact.chats {
                let chat = obj as! Chat
                if chat.messages.count == 0 {
                    collectMessagesForChat(chat)

                    do {
                        try localContext.save()
                        MOCController.sharedInstance.save()
                    } catch let error as NSError {
                        print("ChatsDatabase.collectAllMessagesFromAllChats : worker context save fail : \(error)")
                    }

                }
            }

            indexMessagesForContact(contact)

            DispatchQueue.main.async { taskProgress.completedUnitCount += 1 }
            
        }
    }

    // TODO : this method is probably no longer useful as the whole messages DB is imported at startup anyway
    //
    func collectMessagesForContact(_ contact:ChatContact)
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

    func indexMessagesForContact(_ contact:ChatContact)
    {
        let allMessages = contact.messages.allObjects as! [ChatMessage]

        let allMessagesDateSorted = allMessages.sorted { $0.date.compare($1.date as Date) == .orderedAscending }

        var index:Int64 = 0

        _ = allMessagesDateSorted.map { $0.index = index; index += 1 }

    }

    // MARK: String Search


}
