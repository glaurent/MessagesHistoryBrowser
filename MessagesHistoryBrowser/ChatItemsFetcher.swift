//
//  ChatItemsFetcher.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 31/12/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class ChatItemsFetcher: NSObject {

    static let sharedInstance = ChatItemsFetcher()

    var contact:ChatContact?

    var afterDate:Date?
    var beforeDate:Date?
    var searchTerm:String?

    var matchingItems = [ChatItem]()
    var matchingAttachments = [ChatAttachment]()
    var matchingContacts:[ChatContact]?

    var currentSearchMatchingItems = [ChatItem]()

    typealias SearchCompletionBlock = (([ChatItem], [ChatAttachment], [ChatContact]?) -> (Void))

    var completion:SearchCompletionBlock?

    // Incremented on every request. Asynchronous browse results carry the
    // generation they were issued with and are dropped if a newer request has
    // been made since (e.g. the user clicked through several contacts quickly).
    private var requestGeneration = 0

    let messageDateSort = { (a:AnyObject, b:AnyObject) -> Bool in
        let aItem = a as! ChatItem
        let bItem = b as! ChatItem

        return aItem.dateNanoseconds < bItem.dateNanoseconds
    }

    let messageEnumIteratorDateSort = { (a:NSFastEnumerationIterator.Element, b:NSFastEnumerationIterator.Element) -> Bool in
        let aItem = a as! ChatItem
        let bItem = b as! ChatItem

        return aItem.dateNanoseconds < bItem.dateNanoseconds
    }

    let messageIndexSort = { (a:Any, b:Any) -> Bool in
        let aItem = a as! ChatItem
        let bItem = b as! ChatItem
//        print("a.index : \(aItem.index) - b.index : \(bItem.index)")

        return aItem.index < bItem.index
    }

    // MARK: Entry point - search
    //
    func searchWithCompletionBlock()
    {
        // The selected contact and the results consumed by the UI all belong to
        // the main viewContext. NSManagedObjects must only be touched on their own
        // context's queue, so managed-object work here happens on the main
        // context/queue — except the two genuinely expensive operations, the text
        // search fetch over every message and the ordering of a whole
        // conversation, which are offloaded to a background worker context and
        // only ever hand NSManagedObjectIDs back to the main queue.

        let mainMOC = MOCController.sharedInstance.managedObjectContext

        requestGeneration += 1
        let generation = requestGeneration

        // Browsing a contact (no search term). A conversation can hold tens of
        // thousands of items; faulting them through the contact's relationships
        // on the main thread fires one SELECT per object and stalls the UI, so
        // order them by a lightweight fetch on a worker context instead.
        if let contact = contact, searchTerm == nil {

            let contactID = contact.objectID
            let afterDate = self.afterDate
            let beforeDate = self.beforeDate
            let localMOC = MOCController.sharedInstance.workerContext()

            localMOC.perform {
                let ordered = self.orderedChatItemIDs(forContactWithID: contactID, in: localMOC, afterDate: afterDate, beforeDate: beforeDate)

                DispatchQueue.main.async {
                    // A newer request (another contact, a search, changed date
                    // bounds) supersedes this one.
                    guard generation == self.requestGeneration else { return }

                    // object(with:) returns faults: a row is only read from the
                    // store when its view displays it, so this stays cheap
                    // however large the conversation is.
                    self.matchingItems = ordered.items.map { mainMOC.object(with: $0) as! ChatItem }
                    self.matchingAttachments = ordered.attachments.map { mainMOC.object(with: $0) as! ChatAttachment }
                    self.matchingContacts = nil

                    self.completion?(self.matchingItems, self.matchingAttachments, self.matchingContacts)
                }
            }

            return
        }

        // Text search (no contact selected) requires a fetch across all messages.
        if let searchTerm = searchTerm, contact == nil {

            let localMOC = MOCController.sharedInstance.workerContext()

            localMOC.perform {
                // Runs on the worker queue, touching only the worker context's own objects.
                let messageIDs = self.searchChatsForString(searchTerm, inManagedObjectContext: localMOC, afterDate: self.afterDate, beforeDate: self.beforeDate)

                DispatchQueue.main.async {
                    // Materialize the object IDs and post-process on the main queue / main context.
                    let messages = messageIDs.map { mainMOC.object(with: $0) as! ChatMessage }

                    self.currentSearchMatchingItems = messages
                    self.matchingItems = messages
                    self.matchingAttachments.removeAll()
                    self.matchingContacts = self.contactsFromMessages(messages)

                    self.completion?(self.matchingItems, self.matchingAttachments, self.matchingContacts)
                }
            }

            return
        }

        // Narrowing existing search results to a contact, or clearing — pure
        // in-memory work on main-context objects, so run them synchronously on
        // the main context/queue (this method is called on main).
        search(mainMOC)
        completion?(matchingItems, matchingAttachments, matchingContacts)
    }

    func clearSearch()
    {
        contact = nil
        searchTerm = nil
        matchingContacts = nil
    }

    // use after a search has been restricted to one contact
    // re-instate the search results to all matching contacts
    //
    func restoreSearchToAllContacts()
    {
        matchingItems = currentSearchMatchingItems
    }

    func search(_ moc:NSManagedObjectContext)
    {
        if let contact = contact, searchTerm != nil { // narrow the current search results to one contact

            matchingItems = currentSearchMatchingItems.filter({ (item:ChatItem) -> Bool in
                if let message = item as? ChatMessage {
                    return message.contact == contact
                } else if let attachment = item as? ChatAttachment {
                    return attachment.contact == contact
                }
                return false
            })

        } else if let searchTerm = searchTerm { // no contact, only search term

            matchingAttachments.removeAll()
            let messagesObjectIDs = searchChatsForString(searchTerm, inManagedObjectContext: moc, afterDate: afterDate, beforeDate: beforeDate)

            let mainMOC = MOCController.sharedInstance.managedObjectContext

            // turn those objectIDs into managedObjects from the main MOC which we can then use on the main queue
            //
            let messages = messagesObjectIDs.map { mainMOC.object(with: $0) as! ChatMessage }

            currentSearchMatchingItems = messages
            matchingItems = currentSearchMatchingItems
            matchingContacts = contactsFromMessages(messages)

        } else { // nothing specified - no contact or search term, clear all, all chats will be listed
            matchingContacts = nil
            matchingAttachments.removeAll()
            matchingItems.removeAll()
        }
    }

    // MARK: Browsing a contact's conversation
    // when no search term is specified
    //

    private struct DatedObjectID {
        let objectID: NSManagedObjectID
        let dateNanoseconds: Int64
    }

    // Returns the IDs of the contact's messages and attachments interleaved in
    // chronological order, plus the attachments alone (for the attachments
    // pane). Both lists come out of the store already sorted, so combining
    // them is a single linear merge. Only IDs and timestamps are read
    // (dictionary result type): no managed object is materialized here.
    private func orderedChatItemIDs(forContactWithID contactID: NSManagedObjectID, in moc: NSManagedObjectContext, afterDate: Date?, beforeDate: Date?) -> (items: [NSManagedObjectID], attachments: [NSManagedObjectID])
    {
        let messages = fetchDatedObjectIDs(entityName: ChatMessage.EntityName, contactID: contactID, in: moc, afterDate: afterDate, beforeDate: beforeDate)
        let attachments = fetchDatedObjectIDs(entityName: ChatAttachment.EntityName, contactID: contactID, in: moc, afterDate: afterDate, beforeDate: beforeDate)

        var items = [NSManagedObjectID]()
        items.reserveCapacity(messages.count + attachments.count)

        var messageIndex = 0
        var attachmentIndex = 0
        while messageIndex < messages.count && attachmentIndex < attachments.count {
            if messages[messageIndex].dateNanoseconds <= attachments[attachmentIndex].dateNanoseconds {
                items.append(messages[messageIndex].objectID)
                messageIndex += 1
            } else {
                items.append(attachments[attachmentIndex].objectID)
                attachmentIndex += 1
            }
        }
        items.append(contentsOf: messages[messageIndex...].map { $0.objectID })
        items.append(contentsOf: attachments[attachmentIndex...].map { $0.objectID })

        return (items, attachments.map { $0.objectID })
    }

    // Fetches (objectID, dateNanoseconds) pairs for one ChatItem sub-entity,
    // filtered by contact and optional date bounds, sorted chronologically. The
    // bounds are applied to the indexed `dateNanoseconds` column so SQLite does
    // the filtering and ordering. `afterDate` is inclusive and `beforeDate`
    // exclusive, matching the day-boundary values the view model produces.
    private func fetchDatedObjectIDs(entityName: String, contactID: NSManagedObjectID, in moc: NSManagedObjectContext, afterDate: Date?, beforeDate: Date?) -> [DatedObjectID]
    {
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType

        let objectIDProperty = NSExpressionDescription()
        objectIDProperty.name = "objectID"
        objectIDProperty.expression = NSExpression.expressionForEvaluatedObject()
        objectIDProperty.expressionResultType = .objectIDAttributeType

        request.propertiesToFetch = [objectIDProperty, "dateNanoseconds"]
        request.sortDescriptors = [NSSortDescriptor(key: "dateNanoseconds", ascending: true)]

        var predicates = [NSPredicate(format: "contact == %@", contactID)]
        if let afterDate = afterDate {
            predicates.append(NSPredicate(format: "dateNanoseconds >= %lld", ChatItemsFetcher.nanoseconds(from: afterDate)))
        }
        if let beforeDate = beforeDate {
            predicates.append(NSPredicate(format: "dateNanoseconds < %lld", ChatItemsFetcher.nanoseconds(from: beforeDate)))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        do {
            let rows = try moc.fetch(request)
            return rows.compactMap { row -> DatedObjectID? in
                guard let objectID = row["objectID"] as? NSManagedObjectID,
                      let nanoseconds = row["dateNanoseconds"] as? Int64 else { return nil }
                return DatedObjectID(objectID: objectID, dateNanoseconds: nanoseconds)
            }
        } catch let error as NSError {
            NSLog("\(#function) Could not fetch \(entityName) for contact: \(error), \(error.userInfo)")
            return []
        }
    }

    // Same scale as ChatItem.dateNanoseconds: nanoseconds since the 2001 reference date.
    private static func nanoseconds(from date: Date) -> Int64 {
        return Int64((date.timeIntervalSinceReferenceDate * 1_000_000_000).rounded())
    }


    // MARK: FetchRequest-based search
    //

    // return an array of NSManagedObjectIDs of ChatItems sorted by index
    //
    func searchChatsForString(_ string:String, inManagedObjectContext moc:NSManagedObjectContext, afterDate:Date? = nil, beforeDate:Date? = nil) -> [NSManagedObjectID]
    {
        var result = [NSManagedObjectID]()

        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: ChatMessage.EntityName)
        let argArray:[AnyObject] = [ChatMessage.Attributes.content.rawValue as AnyObject, string as AnyObject]


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
            let matchingMessages = try moc.fetch(fetchRequest)
            let matchingMessagesSorted = (matchingMessages as! [ChatMessage]).sorted(by: messageDateSort) // messages here are from multiple contacts, so use date for global sort

            let matchingMessagesWithSurroundingMessages = addSurroundingMessages(matchingMessagesSorted)

            result = matchingMessagesWithSurroundingMessages.map {$0.objectID}

        } catch let error as NSError {
            print("\(#function) Could not fetch \(error), \(error.userInfo)")
        } catch {
            print("weird fetch error")
        }

        return result
    }

    func splitMessagesPerContact(_ messages:[ChatMessage]) -> [ChatContact:[ChatMessage]]
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

    // nb of messages added before and after a message matching a search term in search results
    //
    let nbOfMessagesBeforeAfter = 2 // TODO: make this user configurable

    func addSurroundingMessages(_ messages:[ChatMessage]) -> [ChatMessage]
    {
        // messages are time-sorted

        var result = [ChatMessage]()

        let messagesSortedPerContact = splitMessagesPerContact(messages)

        for (contact, contactMessages) in messagesSortedPerContact {
            let allContactMessagesSorted = contact.messages.sorted(by: messageIndexSort)
            let allContactMessages = allContactMessagesSorted as! [ChatMessage]

            guard !allContactMessages.isEmpty else { continue }

            // For every matched message, include a window of `nbOfMessagesBeforeAfter`
            // messages on either side. We collect the positions in a Set rather than
            // merging index ranges: message dates are truncated to whole seconds on
            // import, so `message.index` (assigned by one date sort) isn't guaranteed
            // to be monotonic with the search result order (a different date sort).
            // The set is order-independent, self-deduplicating, and can never form an
            // invalid Range.
            let lastPosition = allContactMessages.count - 1
            var positionsToInclude = Set<Int>()

            for message in contactMessages {
                let center = min(max(Int(message.index), 0), lastPosition)
                let lower = max(center - nbOfMessagesBeforeAfter, 0)
                let upper = min(center + nbOfMessagesBeforeAfter, lastPosition)
                for position in lower ... upper {
                    positionsToInclude.insert(position)
                }
            }

            // Emit the included messages in their natural (index) order.
            for position in positionsToInclude.sorted() {
                result.append(allContactMessages[position])
            }
        }

        return result
    }

    // Taken from http://rshankar.com/binary-search-in-swift/
    //
    func messageIndexInDateSortedMessages(_ message:ChatMessage, inMessages allMessages:[ChatMessage]) -> Int
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
                if allMessages[currentIndex].dateNanoseconds > message.dateNanoseconds {
                    upperIndex = currentIndex - 1
                } else {
                    lowerIndex = currentIndex + 1
                }
            }
        }
    }

//    func searchChatsForString(string:String, afterDate:NSDate? = nil, beforeDate:NSDate? = nil, completion:([ChatMessage] -> (Void)))
//    {
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) { () -> Void in
//            
//            let result = self.searchChatsForString(string, afterDate: afterDate, beforeDate: beforeDate)
//            
//            dispatch_async(dispatch_get_main_queue(), { () -> Void in
//                completion(result)
//            })
//        }
//    }

    // Used when searching all messages for a string
    // Given the resulting messages, get all the contacts they come from, so these contacts only are shown in the contact list
    //
    // Deduplicated by managed object identity, not by display name: two distinct
    // contacts sharing a name must both appear in the list.
    func contactsFromMessages(_ messages: [ChatMessage]) -> [ChatContact]
    {
        var seen = Set<NSManagedObjectID>()

        return messages.compactMap { message -> ChatContact? in
            let contact = message.contact
            guard seen.insert(contact.objectID).inserted else { return nil }
            return contact
        }
    }



}
