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

    var afterDate:NSDate?
    var beforeDate:NSDate?
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

        return aItem.date.isLessThan(bItem.date)
    }

    let messageIndexSort = { (a:AnyObject, b:AnyObject) -> Bool in
        let aItem = a as! ChatItem
        let bItem = b as! ChatItem
//        print("a.index : \(aItem.index) - b.index : \(bItem.index)")

        return aItem.index < bItem.index
    }

    // MARK: Entry point - search
    //
    func searchWithCompletionBlock()
    {
        let localMOC = MOCController.sharedInstance.workerContext()

        localMOC.performBlock { () -> Void in
            // call search, collect NSManagedObjectIDs of messages, then use those to display result from main moc in main thread

            self.search(localMOC)

            if let completion = self.completion {
                // run completion block on main queue, passing it the search results
                //
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    completion(self.matchingItems, self.matchingAttachments, self.matchingContacts)
                })
            }
        }

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

    func search(moc:NSManagedObjectContext)
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
                collectChatItemsForContact(contact, afterDate: afterDate, beforeDate: beforeDate)
            }


        } else if let searchTerm = searchTerm { // no contact, only search term

            matchingAttachments.removeAll()
            let messagesObjectIDs = searchChatsForString(searchTerm, inManagedObjectContext: moc, afterDate: afterDate, beforeDate: beforeDate)

            let mainMOC = MOCController.sharedInstance.managedObjectContext

            // turn those objectIDs into managedObjects from the main MOC which we can then use on the main queue
            //
            let messages = messagesObjectIDs.map { mainMOC.objectWithID($0) as! ChatMessage }

            currentSearchMatchingItems = messages
            matchingItems = currentSearchMatchingItems
            matchingContacts = contactsFromMessages(messages)

        } else { // nothing, clear all
            matchingContacts = nil
            matchingAttachments.removeAll()
            matchingItems.removeAll()
        }
    }

    // MARK: Array-based search
    // when no search term is specified
    //
    func collectChatItemsForContact(contact: ChatContact, afterDate:NSDate? = nil, beforeDate:NSDate? = nil)
    {

        let allContactItems = contact.messages.setByAddingObjectsFromSet(contact.attachments as Set<NSObject>)

        let allContactItemsSorted = allContactItems.sort(messageDateSort) as! [ChatItem]

        let contactAttachments = contact.attachments.sort(messageDateSort) as! [ChatAttachment]

        if afterDate != nil || beforeDate != nil {

            matchingItems = filterChatItemsForDateInterval(allContactItemsSorted, afterDate: afterDate, beforeDate: beforeDate)

            matchingAttachments = filterChatItemsForDateInterval(contactAttachments, afterDate: afterDate, beforeDate: beforeDate)

        } else {

            matchingItems = allContactItemsSorted
            matchingAttachments = contactAttachments

        }
    }
    

    func filterChatItemsForDateInterval<T: ChatItem>(chatItems:[T], afterDate:NSDate? = nil, beforeDate:NSDate?) -> [T]
    {
        // filter according to after/before dates
        //
        let filteredContactChatItems = chatItems.filter { (obj:NSObject) -> Bool in
            guard let item = obj as? ChatItem else { return false }

            var res = true
            if let afterDate = afterDate {
                res = afterDate.compare(item.date) == .OrderedAscending

                if !res {
                    return false
                }
            }

            if let beforeDate = beforeDate {
                res = beforeDate.compare(item.date) == .OrderedDescending
            }

            return res
        }

        return filteredContactChatItems.sort(messageDateSort) 

    }


    // MARK: FetchRequest-based search
    //

    // return an array of NSManagedObjectIDs of ChatItems sorted by index
    //
    func searchChatsForString(string:String, inManagedObjectContext moc:NSManagedObjectContext, afterDate:NSDate? = nil, beforeDate:NSDate? = nil) -> [NSManagedObjectID]
    {
        var result = [NSManagedObjectID]()

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
            let matchingMessagesSorted = (matchingMessages as! [ChatMessage]).sort(messageDateSort) // messages here are from multiple contacts, so use date for global sort

            let matchingMessagesWithSurroundingMessages = addSurroundingMessages(matchingMessagesSorted)

            result = matchingMessagesWithSurroundingMessages.map {$0.objectID}

        } catch let error as NSError {
            print("\(__FUNCTION__) : Could not fetch \(error), \(error.userInfo)")
        } catch {
            print("weird fetch error")
        }

        return result
    }

    func splitMessagesPerContact(messages:[ChatMessage]) -> [ChatContact:[ChatMessage]]
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

        let messagesSortedPerContact = splitMessagesPerContact(messages)

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
    func contactsFromMessages(messages: [ChatMessage]) -> [ChatContact]
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
