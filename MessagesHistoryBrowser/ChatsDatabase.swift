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
            return Chat.allChatsInContext(moc)
        }
    }

    var db:Connection!

    lazy var moc = MOCController.sharedInstance.managedObjectContext

    let messageDateSort = { (a:AnyObject, b:AnyObject) -> Bool in
        let aItem = a as! ChatItem
        let bItem = b as! ChatItem

        return aItem.date.isLessThan(bItem.date)
    }

    override init() {

        do {

//            let appDelegate = NSApp.delegate as! AppDelegate
//
//            appDelegate.clearAllCoreData()

            contactsPhoneNumber = ContactsMap.sharedInstance

            db = try Connection(chatsDBPath, readonly:true)

            super.init()

        } catch {
            super.init()
            NSLog("%@ error", __FUNCTION__)
        }

    }


    func populate(progress:NSProgress, completion:() -> Void)
    {
        contactsPhoneNumber.populate({ () -> Void in
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in

                if Chat.allChatsInContext(self.moc).count == 0 {
                    self.importAllChatsFromDB(progress)
                    self.collectAllMessagesFromAllChats(progress)
                }

                // run completion block on main queue
                //
                dispatch_async(dispatch_get_main_queue(), { () -> Void in

                    completion()

                })

            })
        })

    }

    func importAllChatsFromDB(progress:NSProgress)
    {
        NSOperationQueue .mainQueue().addOperationWithBlock({ () -> Void in
            progress.localizedDescription = NSLocalizedString("Importing chats...", comment: "")
        })

        let chats = Table("chat")
        
        let chatRowIDColumn = Expression<Int>("ROWID")
        let chatGUIDColumn = Expression<String>("guid")
        let serviceNameColumn = Expression<String>("service_name")
        let chatIdentifierColumn = Expression<String>("chat_identifier")
        
        // Iterate over all chats
        //

        let nbRows = Int64(db.scalar(chats.count))
        progress.becomeCurrentWithPendingUnitCount(nbRows)


        let chatImportProgress = NSProgress(totalUnitCount: nbRows)
        var rowIndex:Int64 = 0

        let dbRows = db.prepare(chats.select(chatRowIDColumn, chatGUIDColumn, serviceNameColumn, chatIdentifierColumn))

        for chatData in dbRows {
            
            let guid = chatData[chatGUIDColumn]
            let rowID = chatData[chatRowIDColumn]
            let identifier = chatData[chatIdentifierColumn]
            let serviceName = chatData[serviceNameColumn]
            
            let chatContact = contactForIdentifier(identifier, service:serviceName)
            
            let _ = Chat(managedObjectContext:moc, withContact:chatContact, withServiceName:serviceName,  withGUID: guid, andRowID: rowID)
            
            NSLog("chat : %@ \tcontact : %@\trowId: %d", guid, chatContact.name, rowID)

            NSOperationQueue.mainQueue().addOperationWithBlock({ () -> Void in
                chatImportProgress.completedUnitCount = rowIndex
            })

//            dispatch_async(dispatch_get_main_queue(), { (Void) -> Void in
//                progress(rowIndex: rowIndex, totalNbRows: nbRows)
//            })

            ++rowIndex
        }

        progress.resignCurrent()

        MOCController.sharedInstance.save()

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

        let chatInMoc = moc.objectWithID(chat.objectID) as! Chat
        
        for messageData in query {
            let messageContent = messageData[textColumn] ?? ""
            let dateInt = messageData[dateColumn]
            let dateTimeInterval = NSTimeInterval(dateInt)
            let messageDate = NSDate(timeIntervalSinceReferenceDate: dateTimeInterval)
//            NSLog("message : \(messageContent)")

            let chatMessage = ChatMessage(managedObjectContext: moc, withMessage: messageContent, withDate: messageDate, inChat: chatInMoc)
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

            let _ = ChatAttachment(managedObjectContext: moc, withFileName: attachmentFileName, withDate: attachmentDate, inChat:chatInMoc)
        }

    }

    func collectAllMessagesFromAllChats(progress:NSProgress)
    {
        let allContacts = ChatContact.allContactsInContext(moc)
        let allContactsCount = Int64(allContacts.count)

        progress.becomeCurrentWithPendingUnitCount(allContactsCount)

        let messagesImportProgress = NSProgress(totalUnitCount: allContactsCount)

        NSOperationQueue .mainQueue().addOperationWithBlock({ () -> Void in
            progress.localizedDescription = NSLocalizedString("Importing chat messages...", comment: "")
        })

        for contact in allContacts {
            for obj in contact.chats {
                let chat = obj as! Chat
                if chat.messages.count == 0 {
                    messagesForChat(chat)
                }
            }

            NSOperationQueue .mainQueue().addOperationWithBlock({ () -> Void in
                messagesImportProgress.completedUnitCount++
            })
        }

        progress.resignCurrent()
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

    // MARK: String Search

    func searchChatsForString(string:String, afterDate:NSDate? = nil, beforeDate:NSDate? = nil) -> [ChatMessage]
    {
        var result = [ChatMessage]()

        let fetchRequest = NSFetchRequest(entityName: ChatMessage.EntityName)
        let argArray:[AnyObject] = [ChatMessage.Attributes.content.rawValue, string]


        let stringSearchPredicate = NSPredicate(format: "%K CONTAINS %@", argumentArray:argArray)

        var subPredicates = [NSPredicate]()
        
        if let afterDate = afterDate {
            let datePredicate = NSPredicate(format: "%K >= %@", argumentArray: [ChatMessage.Attributes.date.rawValue, afterDate])
            subPredicates.append(datePredicate)
        }
        
        if let beforeDate = beforeDate {
            let datePredicate = NSPredicate(format: "%K <= %@", argumentArray: [ChatMessage.Attributes.date.rawValue, beforeDate])
            subPredicates.append(datePredicate)
        }

        if subPredicates.count > 0 {
            subPredicates.append(stringSearchPredicate)
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
        } else {
            fetchRequest.predicate = stringSearchPredicate
        }

        do {
            let matchingMessages = try moc.executeFetchRequest(fetchRequest)
            result = (matchingMessages as! [ChatMessage]).sort(messageDateSort)

            result = addSurroundingMessages(result)

        } catch let error as NSError {
            print("\(__FUNCTION__) : Could not fetch \(error), \(error.userInfo)")
        }

        return result
    }

    func sortMessagesPerContact(messages:[ChatMessage]) -> [ChatContact:[ChatMessage]]
    {
        var result = [ChatContact:[ChatMessage]]()

        for message in messages {
            if result[message.contact] == nil {
                result[message.contact] = [ChatMessage]()
            }

            result[message.contact]?.append(message)
        }

        return result
    }

    let nbOfMessagesBeforeAfter = 2 // TODO: make this user configurable

    func addSurroundingMessages(messages:[ChatMessage]) -> [ChatMessage]
    {
        // messages are time-sorted

        var result = [ChatMessage]()

        let messagesSortedPerContact = sortMessagesPerContact(messages)

        for (contact, contactMessages) in messagesSortedPerContact {
            let allContactMessages = contact.messages.sort(messageDateSort) as! [ChatMessage]

            var initialMessagesPlusSurroundingMessages = [ChatMessage]()

            var lastSlice = Range<Int>(start:0, end:0)

            for message in contactMessages {
                let (messagesRangeAroundThisMessage, disjointSlice) = surroundingMessagesForMessage(message, inMessages: allContactMessages, numberBeforeAndAfter: nbOfMessagesBeforeAfter, previousSliceRange:lastSlice)

                if disjointSlice {
                    initialMessagesPlusSurroundingMessages.appendContentsOf(allContactMessages[messagesRangeAroundThisMessage])
                }

                lastSlice = messagesRangeAroundThisMessage

            }

            result.appendContentsOf(initialMessagesPlusSurroundingMessages) // TODO: remove duplicates
        }

        return result
    }

    func surroundingMessagesForMessage(message:ChatMessage, inMessages allMessages:[ChatMessage], numberBeforeAndAfter:Int, previousSliceRange:Range<Int>) -> (Range<Int>, Bool)
    {
        let messageIndex = messageIndexInDateSortedMessages(message, inMessages: allMessages)

        let startIndex = max(messageIndex - numberBeforeAndAfter, 0)
        let endIndex = min(messageIndex + numberBeforeAndAfter, allMessages.count - 1)

        var slice = Range<Int>(start: startIndex, end: endIndex)
        var disjointSlice = true

        // check possible join with previous slice
        if startIndex <= previousSliceRange.endIndex {
            slice = Range<Int>(start: previousSliceRange.startIndex, end: endIndex)
            disjointSlice = false
        }

        return (slice, disjointSlice)
    }

    // Taken from http://rshankar.com/binary-search-in-swift/
    //
    func messageIndexInDateSortedMessages(message:ChatMessage, inMessages allMessages:[ChatMessage]) -> Int
    {
        var lowerIndex = 0;
        var upperIndex = allMessages.count - 1

        while (true) {
            let currentIndex = (lowerIndex + upperIndex)/2
            if (allMessages[currentIndex] == message) {
                return currentIndex
            } else if (lowerIndex > upperIndex) {
                return allMessages.count
            } else {
                let messageDateCompare = allMessages[currentIndex].date.compare(message.date)
                if (messageDateCompare == .OrderedDescending) {
                    upperIndex = currentIndex - 1
                } else {
                    lowerIndex = currentIndex + 1
                }
            }
        }
    }

    func searchChatsForString(string:String, afterDate:NSDate? = nil, beforeDate:NSDate? = nil, completion:([ChatMessage] -> (Void)))
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) { () -> Void in
            
            let result = self.searchChatsForString(string, afterDate: afterDate, beforeDate: beforeDate)
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                completion(result)
            })
        }
    }

}
