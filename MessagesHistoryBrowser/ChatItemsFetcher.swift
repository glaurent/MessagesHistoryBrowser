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

    let messageDateSort = { (a:AnyObject, b:AnyObject) -> Bool in
        let aItem = a as! ChatItem
        let bItem = b as! ChatItem

        return aItem.date < bItem.date
    }

    let messageEnumIteratorDateSort = { (a:NSFastEnumerationIterator.Element, b:NSFastEnumerationIterator.Element) -> Bool in
        let aItem = a as! ChatItem
        let bItem = b as! ChatItem

        return aItem.date < bItem.date
    }

    let messageHashableDateSort = { (a:AnyHashable, b:AnyHashable) -> Bool in
        let aItem = a as! ChatItem
        let bItem = b as! ChatItem

        return aItem.date < bItem.date
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
        // context's queue, so all managed-object work here happens on the main
        // context/queue — except the one genuinely expensive operation, the text
        // search fetch over every message, which is offloaded to a background
        // worker context and only ever hands NSManagedObjectIDs back to the main
        // queue.

        let mainMOC = MOCController.sharedInstance.managedObjectContext

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

        // Browsing a contact, narrowing existing search results to a contact, or
        // clearing — all pure in-memory work on main-context objects, so run them
        // synchronously on the main context/queue (this method is called on main).
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
        if let contact = contact {

            if searchTerm != nil {

                matchingItems = currentSearchMatchingItems.filter({ (item:ChatItem) -> Bool in
                    if let message = item as? ChatMessage {
                        return message.contact == contact
                    } else if let attachment = item as? ChatAttachment {
                        return attachment.contact == contact
                    }
                    return false
                })


            } else {
                matchingContacts = nil
                collectChatItemsForContact(contact, moc: moc, afterDate: afterDate, beforeDate: beforeDate)
            }


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

    // MARK: Array-based search
    // when no search term is specified
    //
    func collectChatItemsForContact(_ contact: ChatContact, moc:NSManagedObjectContext, afterDate:Date? = nil, beforeDate:Date? = nil)
    {
        // Access the contact through the context we're executing on, so its
        // relationship faults fire on that context's queue. (For the browse path
        // this is the main context, which already owns `contact`.)
        let localContact = moc.object(with: contact.objectID) as! ChatContact

        let allContactItems = localContact.messages.addingObjects(from: localContact.attachments as Set<NSObject>)

        let allContactItemsSorted = allContactItems.sorted(by: messageHashableDateSort) as! [ChatItem]

        let contactAttachments = localContact.attachments.sorted(by: messageEnumIteratorDateSort) as! [ChatAttachment]

        if afterDate != nil || beforeDate != nil {

            matchingItems = filterChatItemsForDateInterval(allContactItemsSorted, afterDate: afterDate, beforeDate: beforeDate)

            matchingAttachments = filterChatItemsForDateInterval(contactAttachments, afterDate: afterDate, beforeDate: beforeDate)

        } else {

            matchingItems = allContactItemsSorted
            matchingAttachments = contactAttachments

        }
    }
    

    func filterChatItemsForDateInterval<T: ChatItem>(_ chatItems:[T], afterDate:Date? = nil, beforeDate:Date?) -> [T]
    {
        // filter according to after/before dates
        //
        let filteredContactChatItems = chatItems.filter { (obj:NSObject) -> Bool in
            guard let item = obj as? ChatItem else { return false }

            var res = true
            if let afterDate = afterDate {
                res = afterDate.compare(item.date as Date) == .orderedAscending

                if !res {
                    return false
                }
            }

            if let beforeDate = beforeDate {
                res = beforeDate.compare(item.date as Date) == .orderedDescending
            }

            return res
        }

        return filteredContactChatItems.sorted(by: messageDateSort)

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
                let messageDateCompare = allMessages[currentIndex].date.compare(message.date as Date)
                if (messageDateCompare == .orderedDescending) {
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
    func contactsFromMessages(_ messages: [ChatMessage]) -> [ChatContact]
    {
        let allContacts = messages.map { (message) -> ChatContact in
            return message.contact
        }

        var contactList = [String:ChatContact]()

        let uniqueContacts = allContacts.filter { (contact) -> Bool in
            if contactList[contact.name] != nil {
                return false
            }
            contactList[contact.name] = contact
            return true
        }

        return uniqueContacts
    }



}
