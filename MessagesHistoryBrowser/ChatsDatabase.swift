//
//  ChatsDatabase.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 04/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import SQLite

class ChatsDatabase {

    enum ChatasDatabaseError : Error {
        case DBConnectionFailed
    }

//    let chatsDBPath = "/Users/glaurent/tmp/chat.db"

    var contactsPhoneNumberMap:ContactsMap! // want delayed init

    var allChats:[Chat] {
        get {
            return Chat.allChatsInContext(MOCController.sharedInstance.managedObjectContext)
        }
    }

    var db:Connection!

    init(chatsDBPath:String) throws {

        contactsPhoneNumberMap = ContactsMap.sharedInstance

        do {

            db = try Connection(chatsDBPath, readonly:true)

        } catch let error {

            NSLog("\(#function) error : \(error)")
            throw ChatasDatabaseError.DBConnectionFailed
        }

    }

    func populate(_ progress:Progress) async
    {
        let defaultCountryPhonePrefix = UserDefaults.standard.string(forKey: CountryPhonePrefixUserDefaultsKey) ?? "+33"
        _ = contactsPhoneNumberMap.populate(withCountryPhonePrefix: defaultCountryPhonePrefix)

//        let workerContext = MOCController.sharedInstance.workerContext()

        let persistentContainer = MOCController.sharedInstance.persistentContainer

        await persistentContainer.performBackgroundTask { (workerContext) in

            if Chat.numberOfChatsInContext(workerContext) == 0 {

                DispatchQueue.main.async {
                    progress.localizedDescription = NSLocalizedString("Importing chats...", comment: "")
                    progress.localizedAdditionalDescription = ""
                }
                progress.becomeCurrent(withPendingUnitCount: 2)

                ImportLogsContainer.log("Importing chats")
                self.importAllChatsFromDB(workerContext)

                progress.resignCurrent()
                DispatchQueue.main.async {
                    progress.localizedDescription = NSLocalizedString("Importing chat messages...", comment: "")
                }
                progress.becomeCurrent(withPendingUnitCount: 8) // must be a total 10 units - see init of Progress in ChatTableViewController.setupProgressBeforeImport()

                self.collectAllMessagesFromAllChats(workerContext)

                progress.resignCurrent()
            }

            do {
                try workerContext.save()
//                MOCController.sharedInstance.save()
            } catch let error as NSError {
                NSLog("\(#function) : worker context save fail : \(error)")
            }
        }

    }

    func importAllChatsFromDB(_ localContext:NSManagedObjectContext)
    {
        ImportLogsContainer.clear()

        let chats = Table("chat")
        
        let chatRowIDColumn = Expression<Int>("ROWID")
        let chatGUIDColumn = Expression<String>("guid")
        let serviceNameColumn = Expression<String>("service_name")
        let chatIdentifierColumn = Expression<String>("chat_identifier")
        
        // Iterate over all chats
        //

        do {

            let nbRows = try Int64(db.scalar(chats.count))
            let taskProgress = Progress(totalUnitCount: nbRows)

            var rowIndex:Int64 = 0


            let dbRows = try db.prepare(chats.select(chatRowIDColumn, chatGUIDColumn, serviceNameColumn, chatIdentifierColumn))

            ImportLogsContainer.log("dbRows underestimated count: \(dbRows.underestimatedCount)")

            for chatData in dbRows {

                let guid = chatData[chatGUIDColumn]
                let rowID = chatData[chatRowIDColumn]
                let chatIdentifier = chatData[chatIdentifierColumn]
                let serviceName = chatData[serviceNameColumn]

                NSLog("\(#function) contact chat identifier \(chatIdentifier)")
                ImportLogsContainer.log("contact chat guid \(guid) - \(chatIdentifier)")

                let chatContact = contactForChatIdentifier(chatIdentifier, service:serviceName, inContext: localContext)

                let _ = Chat(managedObjectContext:localContext, withContact:chatContact, withServiceName:serviceName,  withGUID: guid, andRowID: rowID)

//            NSLog("chat : %@ \tcontact : %@\trowId: %d", guid, chatContact.name, rowID)

                DispatchQueue.main.async {
                    taskProgress.completedUnitCount = rowIndex
                }
                rowIndex += 1

            }

            do {
                try localContext.save()
            } catch let error as NSError {
                NSLog("\(#function) : worker context save fail : \(error)")
            }

        } catch {
            NSLog("\(#function) : error when preparing DB select")
        }
    }


    func contactForChatIdentifier(_ chatIdentifier:String, service serviceName:String, inContext context:NSManagedObjectContext) -> ChatContact
    {
        var contactName = chatIdentifier // use chatIdentifier as default name
        var contactIsKnown = false
        var contactCNIdentifier = ""

        if serviceName == "AIM" || serviceName == "Jabber" {

            if let chatContactNameIdentifierPair = contactsPhoneNumberMap.nameForInstantMessageAddress(chatIdentifier) {
                contactName = chatContactNameIdentifierPair.0
                contactCNIdentifier = chatContactNameIdentifierPair.1
                contactIsKnown = true
            } else {
                contactIsKnown = false
                NSLog("\(#function) : no contact name found for identifier \(chatIdentifier)")
            }

        } else if serviceName == "iMessage" || serviceName == "SMS" {

            // check if identifier contains a '@'
            if chatIdentifier.contains("@") {
                if let chatContactNameIdentifierPair = contactsPhoneNumberMap.nameForEmailAddress(chatIdentifier) {
                    contactName = chatContactNameIdentifierPair.0
                    contactCNIdentifier = chatContactNameIdentifierPair.1
                    contactIsKnown = true
                }
            } else if let chatContactNameIdentifierPair = contactsPhoneNumberMap.nameForPhoneNumber(chatIdentifier) {
                contactName = chatContactNameIdentifierPair.0
                contactCNIdentifier = chatContactNameIdentifierPair.1
                contactIsKnown = true
            } else {
                contactName = chatIdentifier
                contactIsKnown = false
            }
        } else {
            contactName = chatIdentifier
            contactIsKnown = false
        }

//        contactsPhoneNumber.nameAndCNIdentifierFromChatIdentifier(identifier, serviceName: serviceName) { (contactAndCNIdentifierPair, contactIsKnown) in
//            var contactName = identifier
//            var contactCNIdentifier = ""
//
//            if let contactAndCNIdentifierPair = contactAndCNIdentifierPair {
//                contactName = contactAndCNIdentifierPair.0
//                contactCNIdentifier = contactAndCNIdentifierPair.1
//            }
//
//            let contact = ChatContact.contactIn(context, named: contactName, withIdentifier: contactCNIdentifier)
//            contact.known = contactIsKnown
//
//            completion(contact)
//        }

        let contact = ChatContact.contactIn(context, named: contactName, withIdentifier: contactCNIdentifier)
        contact.known = contactIsKnown
        return contact
    }

    func messagesForChat(_ chat:Chat) -> ([ChatMessage], [ChatAttachment])
    {
        let allMessages = chat.messages.allObjects as! [ChatMessage]

        let allMessagesSorted = allMessages.sorted { $0.date.compare($1.date as Date) == .orderedAscending }

        let allAttachments = chat.attachments.allObjects as! [ChatAttachment]
        let allAttachmentsSorted = allAttachments.sorted { $0.date.compare($1.date as Date) == .orderedAscending }

        return (allMessagesSorted, allAttachmentsSorted)
    
    }

    func collectMessagesForChat(_ chat:Chat, workerContext:NSManagedObjectContext)
    {
        let messageSaveThreshold = 300

        do {
            let messagesTable  = Table("message")
            let isFromMeColumn = Expression<Bool>("is_from_me")
            let textColumn     = Expression<String?>("text")
            let attributedBodyColumn = Expression<Blob?>("attributedBody") // modern Messages stores the body here when `text` is NULL
            let dateColumn     = Expression<Int>("date")

//            let dateDeliveredColumn = Expression<Int>("date_delivered") // used only for sanity check on dateColumn value

            let chatTable   = Table("chat")
            let rowIDColumn = Expression<Int>("ROWID")
            let guidColumn  = Expression<String>("guid")

            // Resolve the chat's ROWID(s) from its GUID.
            let chatIDQuery = try db.prepare(chatTable.select(rowIDColumn).filter(guidColumn == chat.guid))
            var allRowIDs = [Int]()
            for row in chatIDQuery {
                allRowIDs.append(row[rowIDColumn])
            }

            // Messages belong to a chat through chat_message_join (chat_id -> message_id).
            // The previous approach matched messages by the chat participants' handle_id,
            // which dropped every outgoing message (is_from_me = 1 rows have handle_id = 0,
            // never present in the participant handle list) and left some chats empty.
            let chatMessageJoinTable = Table("chat_message_join")
            let cmjChatIDColumn      = Expression<Int>("chat_id")
            let cmjMessageIDColumn   = Expression<Int>("message_id")

            let messageIDsQuery = try db.prepare(chatMessageJoinTable.select(cmjMessageIDColumn).filter(allRowIDs.contains(cmjChatIDColumn)))
            var allMessageIDs = [Int]()
            for row in messageIDsQuery {
                allMessageIDs.append(row[cmjMessageIDColumn])
            }

            ImportLogsContainer.log("Fetching messages for chat \(chat.guid) - contact \(chat.contact.identifier)")

            let query = try db.prepare(messagesTable.select(rowIDColumn, isFromMeColumn, textColumn, attributedBodyColumn, dateColumn).filter(allMessageIDs.contains(rowIDColumn)))

            var messageCounterSave = 0

            // logging
            var messageCounter = 0
            var firstDate: Date?
            var lastDate = Date()
            var messagesFromMeCounter = 0

            for messageData in query {
                var messageContent = messageData[textColumn] ?? ""

                // On recent macOS the `text` column is NULL and the message body is
                // archived in `attributedBody`. Fall back to decoding it.
                if messageContent.isEmpty, let bodyBlob = messageData[attributedBodyColumn] {
                    if let decoded = ChatsDatabase.messageText(fromAttributedBody: Data(bodyBlob.bytes)) {
                        messageContent = decoded
                    }
                }

                var dateInt = messageData[dateColumn]
                if dateInt > Int(10e9) { // I have this case of timestamp values being multiplied by 10e8 on my iMac running High Sierra, with no apparent effect on the values displayed in the chats history
                    dateInt = dateInt / Int(10e8)
                }
                let dateTimeInterval = TimeInterval(dateInt)
                let messageDate = Date(timeIntervalSinceReferenceDate: dateTimeInterval)

                if firstDate == nil {
                    firstDate = messageDate
                }
                lastDate = messageDate

//              NSLog("message : \(messageContent)")

                let chatMessage = ChatMessage(managedObjectContext: workerContext, withMessage: messageContent, withDate: messageDate, inChat: chat)
                chatMessage.isFromMe = messageData[isFromMeColumn]

                messageCounterSave += 1
                messageCounter += 1
                if chatMessage.isFromMe {
                    messagesFromMeCounter += 1
                }

                if messageCounterSave >= messageSaveThreshold {
                    messageCounterSave = 0
                    do {
                        try workerContext.save()
//                        MOCController.sharedInstance.save()
                    } catch let error as NSError {
                        print("ChatsDatabase.collectMessagesForChat : worker context save fail : \(error)")
                        ImportLogsContainer.log("ChatsDatabase.collectMessagesForChat : worker context save fail : \(error)")
                    }
                }
            }

            ImportLogsContainer.log("Found \(messageCounter) messages - \(messagesFromMeCounter) outgoing messages spanning from \(firstDate ?? Date()) to \(lastDate) in chat")


            // attachments
            //
            let attachments = Table("attachment")
            let filenameColumn = Expression<String?>("filename")
            let attachmentIdColumn = Expression<Int>("attachment_id")
            let isOutgoingColumn = Expression<Bool>("is_outgoing")
            let cacheHasAttachmentColumn = Expression<Bool>("cache_has_attachments")

            let messagesWithAttachmentsROWIDsQuery = try db.prepare(messagesTable.select(rowIDColumn, cacheHasAttachmentColumn).filter(allMessageIDs.contains(rowIDColumn) && cacheHasAttachmentColumn == true))

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

            let attachmentDataQuery = try db.prepare(attachments.select(rowIDColumn, filenameColumn, attachmentDateColumn, isOutgoingColumn).filter(allAttachmentIDs.contains(rowIDColumn)))

            for attachmentData in attachmentDataQuery {
                let attachmentFileName:String? = attachmentData[filenameColumn]
                let attachmentDateInt = attachmentData[attachmentDateColumn]
                let attachmentTimeInterval = TimeInterval(attachmentDateInt)
                let attachmentDate = Date(timeIntervalSinceReferenceDate: attachmentTimeInterval)

//                ImportLogsContainer.log("attachmentFileName : \(attachmentFileName ?? "nil") - attachmentDate : \(attachmentDate) - isFromMe : \(attachmentData[isOutgoingColumn])")
                if let attachmentFileName = attachmentFileName {
                    let chatAttachment = ChatAttachment(managedObjectContext: chat.managedObjectContext!, withFileName: attachmentFileName, withDate: attachmentDate as Date, inChat:chat)
                    chatAttachment.isFromMe = attachmentData[isOutgoingColumn]
                }
            }
            
        } catch {
            NSLog("\(#function) : error when preparing DB select")
        }

    }

    func collectAllMessagesFromAllChats(_ workerContext:NSManagedObjectContext)
    {
        let allContacts = ChatContact.allContacts(workerContext)
        let allContactsCount = Int64(allContacts.count)

        let taskProgress = Progress(totalUnitCount: allContactsCount)

        for contact in allContacts {

            if let currentProgress = Progress.current() {
                DispatchQueue.main.async {
                    currentProgress.localizedAdditionalDescription = contact.name
                }
            }

            for obj in contact.chats {
                let chat = obj as! Chat
                if chat.messages.count == 0 {
                    collectMessagesForChat(chat, workerContext: workerContext)

                    do {
                        try workerContext.save()
//                        MOCController.sharedInstance.save()
                    } catch let error as NSError {
                        print("ChatsDatabase.collectAllMessagesFromAllChats : worker context save fail : \(error)")
                    }

                }
            }

            indexMessagesForContact(contact)

            DispatchQueue.main.async {
                taskProgress.completedUnitCount += 1
            }
            
        }

//        DispatchQueue.main.async { Progress.current()?.resignCurrent() }
    }

    // MARK: - attributedBody decoding

    // Extracts the plain message text from an `attributedBody` blob. That column
    // holds an NSAttributedString archived in the legacy `typedstream` format
    // (NSArchiver, not NSKeyedArchiver), so it can't be un-archived with the
    // modern Foundation APIs. We parse it directly: find the `NSString` class
    // marker, skip its fixed version header (01 94 84 01 2B), then read the
    // length-prefixed UTF-8 string that follows.
    static func messageText(fromAttributedBody data: Data) -> String? {
        let bytes = [UInt8](data)

        guard let markerEnd = firstIndex(of: Array("NSString".utf8), in: bytes) else { return nil }

        // Skip the 5 header bytes that follow the class name (01 94 84 01 2B).
        var idx = markerEnd + 5
        guard idx < bytes.count else { return nil }

        // Length prefix: one byte, or an escape (0x81 / 0x82) introducing a
        // 2- or 3-byte little-endian length for longer strings.
        var length = Int(bytes[idx]); idx += 1
        switch length {
        case 0x81:
            guard idx + 1 < bytes.count else { return nil }
            length = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
            idx += 2
        case 0x82:
            guard idx + 2 < bytes.count else { return nil }
            length = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8) | (Int(bytes[idx + 2]) << 16)
            idx += 3
        default:
            break
        }

        guard length > 0, idx + length <= bytes.count else { return nil }
        return String(bytes: bytes[idx ..< idx + length], encoding: .utf8)
    }

    // Returns the index just past the first occurrence of `pattern` in `bytes`.
    private static func firstIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        for start in 0 ... (bytes.count - pattern.count) {
            var matched = true
            for offset in 0 ..< pattern.count where bytes[start + offset] != pattern[offset] {
                matched = false
                break
            }
            if matched { return start + pattern.count }
        }
        return nil
    }

    func indexMessagesForContact(_ contact:ChatContact)
    {
        let allMessages = contact.messages.allObjects as! [ChatMessage]

        let allMessagesDateSorted = allMessages.sorted { $0.date.compare($1.date as Date) == .orderedAscending }

        var index:Int64 = 0

        _ = allMessagesDateSorted.map { $0.index = index; index += 1 }

    }


}
