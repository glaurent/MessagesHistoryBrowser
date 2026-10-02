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

    var db:Connection!

    // Number of inserted messages between two save-and-reset cycles of the
    // worker context during import (see collectMessages(forContactWithID:in:)).
    let messagesPerSave = 1000

    init(chatsDBPath:String) throws {

        contactsPhoneNumberMap = ContactsMap.sharedInstance

        do {

            db = try Connection(chatsDBPath, readonly:true)

        } catch let error {

            NSLog("\(#function) error : \(error)")
            throw ChatasDatabaseError.DBConnectionFailed
        }

    }

    // Imports chats and messages from chat.db, resolving each chat handle to
    // a Contacts framework contact where possible. Returns whether Contacts
    // access was available for that resolution, so the caller can tell the
    // user when it wasn't (every chat then falls back to its raw phone
    // number, email address, or handle as its display name).
    @discardableResult
    func populate(_ progress:Progress) async -> Bool
    {
        let contactsAccessGranted = await contactsPhoneNumberMap.requestAccessIfNeeded()
        if !contactsAccessGranted {
            NSLog("Contacts access was not granted: chats will show phone numbers, email addresses, or handles instead of contact names.")
        }

        let persistentContainer = MOCController.sharedInstance.persistentContainer

        // Progress is thread-safe and its observers coalesce notifications (see
        // ObservableProgress), so it is updated directly from this thread
        // rather than through one main-queue block per update.
        await persistentContainer.performBackgroundTask { (workerContext) in

            // Nothing is ever undone during an import; an undo manager would
            // only retain every inserted object.
            workerContext.undoManager = nil

            if Chat.numberOfChatsInContext(workerContext) == 0 {

                progress.localizedDescription = NSLocalizedString("Importing chats...", comment: "")
                progress.localizedAdditionalDescription = ""
                progress.becomeCurrent(withPendingUnitCount: 2)

                NSLog("Importing chats")
                self.importAllChatsFromDB(workerContext)

                progress.resignCurrent()
                progress.localizedDescription = NSLocalizedString("Importing chat messages...", comment: "")
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

        return contactsAccessGranted
    }

    func importAllChatsFromDB(_ localContext:NSManagedObjectContext)
    {
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

            NSLog("dbRows underestimated count: \(dbRows.underestimatedCount)")

            for chatData in dbRows {

                let guid = chatData[chatGUIDColumn]
                let rowID = chatData[chatRowIDColumn]
                let chatIdentifier = chatData[chatIdentifierColumn]
                let serviceName = chatData[serviceNameColumn]

                // NSLog is an in-memory array append; NSLog
                // additionally formats, timestamps, and writes to the system
                // log, which adds up over the thousands of chats a real
                // Messages database can hold.
                NSLog("contact chat guid \(guid) - \(chatIdentifier)")

                let chatContact = contactForChatIdentifier(chatIdentifier, service:serviceName, inContext: localContext)

                let _ = Chat(managedObjectContext:localContext, withContact:chatContact, withServiceName:serviceName,  withGUID: guid, andRowID: rowID)

//            NSLog("chat : %@ \tcontact : %@\trowId: %d", guid, chatContact.name, rowID)

                rowIndex += 1
                taskProgress.completedUnitCount = rowIndex

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

    // Converts a raw Messages timestamp (seconds or nanoseconds since the 2001
    // reference date) into an exact nanosecond value plus a display Date.
    static func normalizedTime(fromRawTimestamp raw: Int) -> (nanoseconds: Int64, date: Date) {
        let nanoseconds: Int64
        if raw > Int(10e9) {
            nanoseconds = Int64(raw)                     // already nanoseconds
        } else {
            nanoseconds = Int64(raw) * 1_000_000_000     // seconds -> nanoseconds
        }
        let date = Date(timeIntervalSinceReferenceDate: Double(nanoseconds) / 1_000_000_000)
        return (nanoseconds, date)
    }

    func messagesForChat(_ chat:Chat) -> ([ChatMessage], [ChatAttachment])
    {
        let allMessages = chat.messages.allObjects as! [ChatMessage]

        let allMessagesSorted = allMessages.sorted { $0.dateNanoseconds < $1.dateNanoseconds }

        let allAttachments = chat.attachments.allObjects as! [ChatAttachment]
        let allAttachmentsSorted = allAttachments.sorted { $0.dateNanoseconds < $1.dateNanoseconds }

        return (allMessagesSorted, allAttachmentsSorted)

    }

    // MARK: - Messages import

    // Imports the messages and attachments of one contact, across all of that
    // contact's chats (a contact often has both an SMS and an iMessage chat).
    //
    // Messages are read from chat.db already in date order, so each message's
    // `index` (its position in the conversation, used to find a search match's
    // neighbours) is assigned as it is created. The previous approach imported
    // chat by chat, then re-loaded every message of the contact to sort and
    // number it, which dirtied and re-wrote all of them on the next save.
    //
    // Memory: the worker context is saved and reset every `messagesPerSave`
    // messages, so imported objects are released as the import proceeds
    // instead of accumulating for the whole run. Only object IDs survive a
    // reset; the contact and chats are re-resolved from their IDs afterwards.
    func collectMessages(forContactWithID contactID: NSManagedObjectID, in workerContext: NSManagedObjectContext)
    {
        var contact = workerContext.object(with: contactID) as! ChatContact

        // The contact's chats, keyed by their ROWID in chat.db (recorded when
        // the chats were imported).
        var chatIDsByRowID = [Int: NSManagedObjectID]()
        for case let chat as Chat in contact.chats {
            chatIDsByRowID[chat.rowID.intValue] = chat.objectID
        }
        guard !chatIDsByRowID.isEmpty else { return }

        var chatsByRowID = chatIDsByRowID.mapValues { workerContext.object(with: $0) as! Chat }
        let chatRowIDs = Array(chatIDsByRowID.keys)

        NSLog("Fetching messages for contact \(contact.name) - \(chatRowIDs.count) chat(s)")

        // Persists what has been inserted so far, drops it from memory, and
        // re-resolves the objects the loops keep using.
        func saveAndReset() {
            do {
                try workerContext.save()
            } catch let error as NSError {
                NSLog("\(#function) : worker context save fail : \(error)")
            }
            workerContext.reset()
            contact = workerContext.object(with: contactID) as! ChatContact
            chatsByRowID = chatIDsByRowID.mapValues { workerContext.object(with: $0) as! Chat }
        }

        // Tables and columns of chat.db.
        let messagesTable        = Table("message")
        let rowIDColumn          = Expression<Int>("ROWID")
        let isFromMeColumn       = Expression<Bool>("is_from_me")
        let textColumn           = Expression<String?>("text")
        let attributedBodyColumn = Expression<Blob?>("attributedBody") // modern Messages stores the body here when `text` is NULL
        let dateColumn           = Expression<Int>("date")

        // Messages belong to a chat through chat_message_join (chat_id -> message_id).
        // Matching by the participants' handle_id instead would drop every
        // outgoing message (is_from_me = 1 rows have handle_id = 0).
        let chatMessageJoinTable = Table("chat_message_join")
        let cmjChatIDColumn      = Expression<Int>("chat_id")
        let cmjMessageIDColumn   = Expression<Int>("message_id")

        let attachmentsTable     = Table("attachment")
        let filenameColumn       = Expression<String?>("filename")
        let createdDateColumn    = Expression<Int>("created_date")
        let isOutgoingColumn     = Expression<Bool>("is_outgoing")

        let messageAttachmentJoinTable = Table("message_attachment_join")
        let majMessageIDColumn         = Expression<Int>("message_id")
        let majAttachmentIDColumn      = Expression<Int>("attachment_id")

        // `date` holds seconds in old rows and nanoseconds in newer ones (see
        // normalizedTime), so order on the normalized value, not the raw one,
        // for the assigned indexes to follow true chronology.
        let normalizedDate = Expression<Int>(literal: "CASE WHEN message.date > 10000000000 THEN message.date ELSE message.date * 1000000000 END")

        do {
            // Messages, oldest first.
            let messagesQuery = messagesTable
                .select(messagesTable[rowIDColumn], messagesTable[isFromMeColumn], messagesTable[textColumn], messagesTable[attributedBodyColumn], messagesTable[dateColumn], chatMessageJoinTable[cmjChatIDColumn])
                .join(chatMessageJoinTable, on: chatMessageJoinTable[cmjMessageIDColumn] == messagesTable[rowIDColumn])
                .filter(chatRowIDs.contains(chatMessageJoinTable[cmjChatIDColumn]))
                .order(normalizedDate, messagesTable[rowIDColumn])

            var index: Int64 = 0
            var insertedSinceSave = 0

            // logging
            var firstDate: Date?
            var lastDate = Date()
            var messagesFromMeCounter = 0

            for messageData in try db.prepare(messagesQuery) {
                guard let chat = chatsByRowID[messageData[chatMessageJoinTable[cmjChatIDColumn]]] else { continue }

                var messageContent = messageData[messagesTable[textColumn]] ?? ""

                // On recent macOS the `text` column is NULL and the message body is
                // archived in `attributedBody`. Fall back to decoding it.
                if messageContent.isEmpty, let bodyBlob = messageData[messagesTable[attributedBodyColumn]] {
                    if let decoded = ChatsDatabase.messageText(fromAttributedBody: Data(bodyBlob.bytes)) {
                        messageContent = decoded
                    }
                }

                // Keep the exact nanosecond timestamp as the source of truth; the
                // Date is derived from it (with fractional seconds) for display.
                let (messageNanoseconds, messageDate) = ChatsDatabase.normalizedTime(fromRawTimestamp: messageData[messagesTable[dateColumn]])

                if firstDate == nil {
                    firstDate = messageDate
                }
                lastDate = messageDate

                let chatMessage = ChatMessage(managedObjectContext: workerContext, withMessage: messageContent, withDate: messageDate, inChat: chat)
                chatMessage.dateNanoseconds = messageNanoseconds
                chatMessage.isFromMe = messageData[messagesTable[isFromMeColumn]]
                chatMessage.index = index
                index += 1

                if chatMessage.isFromMe {
                    messagesFromMeCounter += 1
                }

                insertedSinceSave += 1
                if insertedSinceSave >= messagesPerSave {
                    saveAndReset()
                    insertedSinceSave = 0
                }
            }

            NSLog("Found \(index) messages - \(messagesFromMeCounter) outgoing messages spanning from \(firstDate ?? Date()) to \(lastDate) for contact \(contact.name)")

            // Attachments: attachment -> message_attachment_join -> chat_message_join.
            // DISTINCT because the join tables may link one attachment to
            // several messages of the same chat.
            let attachmentsQuery = attachmentsTable
                .select(distinct: attachmentsTable[rowIDColumn], attachmentsTable[filenameColumn], attachmentsTable[createdDateColumn], attachmentsTable[isOutgoingColumn], chatMessageJoinTable[cmjChatIDColumn])
                .join(messageAttachmentJoinTable, on: messageAttachmentJoinTable[majAttachmentIDColumn] == attachmentsTable[rowIDColumn])
                .join(chatMessageJoinTable, on: chatMessageJoinTable[cmjMessageIDColumn] == messageAttachmentJoinTable[majMessageIDColumn])
                .filter(chatRowIDs.contains(chatMessageJoinTable[cmjChatIDColumn]))

            for attachmentData in try db.prepare(attachmentsQuery) {
                guard let chat = chatsByRowID[attachmentData[chatMessageJoinTable[cmjChatIDColumn]]],
                      let attachmentFileName = attachmentData[attachmentsTable[filenameColumn]] else { continue }

                let (attachmentNanoseconds, attachmentDate) = ChatsDatabase.normalizedTime(fromRawTimestamp: attachmentData[attachmentsTable[createdDateColumn]])

                let chatAttachment = ChatAttachment(managedObjectContext: workerContext, withFileName: attachmentFileName, withDate: attachmentDate, inChat: chat)
                chatAttachment.dateNanoseconds = attachmentNanoseconds
                chatAttachment.isFromMe = attachmentData[attachmentsTable[isOutgoingColumn]]
            }

        } catch {
            NSLog("\(#function) : error when querying chat.db : \(error)")
        }

        saveAndReset()
    }

    func collectAllMessagesFromAllChats(_ workerContext:NSManagedObjectContext)
    {
        // Only object IDs are kept across iterations: the context is reset
        // during each contact's import, which invalidates object references.
        let contactIDs = ChatContact.allContacts(workerContext).map { $0.objectID }

        let taskProgress = Progress(totalUnitCount: Int64(contactIDs.count))
        let currentProgress = Progress.current()

        for contactID in contactIDs {

            let contact = workerContext.object(with: contactID) as! ChatContact
            currentProgress?.localizedAdditionalDescription = contact.name

            collectMessages(forContactWithID: contactID, in: workerContext)

            taskProgress.completedUnitCount += 1
        }
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

}
