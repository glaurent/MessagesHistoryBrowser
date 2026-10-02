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

    // Layout of `currentSearchMatchingItems`: results are grouped per matched
    // contact, and this records each group's range. Narrowing the results to
    // one contact is then a slice, instead of a scan that faults every result
    // message just to read its contact.
    private var currentSearchGroups = [SearchResult.Group]()

    typealias SearchCompletionBlock = (([ChatItem], [ChatAttachment], [ChatContact]?) -> (Void))

    var completion:SearchCompletionBlock?

    // Incremented on every request. Asynchronous browse results carry the
    // generation they were issued with and are dropped if a newer request has
    // been made since (e.g. the user clicked through several contacts quickly).
    private var requestGeneration = 0

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

            let afterDate = self.afterDate
            let beforeDate = self.beforeDate
            let localMOC = MOCController.sharedInstance.workerContext()

            localMOC.perform {
                // Runs on the worker queue, touching only the worker context's own objects.
                let found = self.searchChatsForString(searchTerm, inManagedObjectContext: localMOC, afterDate: afterDate, beforeDate: beforeDate)

                DispatchQueue.main.async {
                    // A newer request supersedes this one.
                    guard generation == self.requestGeneration else { return }

                    // The messages become faults, each read from the store only
                    // when its row is displayed. The matched contacts, on the
                    // other hand, are few and the sidebar shows them all at once,
                    // so they are loaded with a single fetch. Nothing here fires
                    // a fault per result.
                    let messages = found.messageIDs.map { mainMOC.object(with: $0) as! ChatItem }
                    let contacts = self.contacts(withIDs: found.contactIDs, in: mainMOC)

                    self.currentSearchMatchingItems = messages
                    self.currentSearchGroups = found.groups
                    self.matchingItems = messages
                    self.matchingAttachments.removeAll()
                    self.matchingContacts = contacts

                    self.completion?(self.matchingItems, self.matchingAttachments, self.matchingContacts)
                }
            }

            return
        }

        // Narrowing existing search results to a contact, or clearing — pure
        // in-memory work on main-context objects, so run them synchronously on
        // the main context/queue (this method is called on main).
        search()
        completion?(matchingItems, matchingAttachments, matchingContacts)
    }

    // Drops the current request and every result. Used before the store is
    // cleared for a re-import, so no soon-to-be-deleted object stays referenced
    // here, and so a request still in flight is discarded when it completes
    // rather than materializing IDs that no longer exist.
    func reset()
    {
        requestGeneration += 1
        contact = nil
        searchTerm = nil
        matchingItems.removeAll()
        matchingAttachments.removeAll()
        matchingContacts = nil
        currentSearchMatchingItems.removeAll()
        currentSearchGroups.removeAll()
    }

    // Synchronous, main-queue part of a request: narrowing the current search
    // results to the selected contact, or clearing everything. (Searching and
    // browsing are asynchronous and handled in searchWithCompletionBlock.)
    func search()
    {
        if let contact = contact, searchTerm != nil { // narrow the current search results to one contact

            // Results are grouped per contact, so this is a slice: no result
            // object is touched, hence no fault is fired.
            let contactID = contact.objectID
            if let group = currentSearchGroups.first(where: { $0.contactID == contactID }) {
                matchingItems = Array(currentSearchMatchingItems[group.range])
            } else {
                matchingItems = []
            }

        } else { // nothing specified - no contact or search term, clear all, all chats will be listed
            matchingContacts = nil
            matchingAttachments.removeAll()
            matchingItems.removeAll()
        }
    }

    // Materializes the given contacts with a single fetch, in the order of `ids`.
    private func contacts(withIDs ids: [NSManagedObjectID], in moc: NSManagedObjectContext) -> [ChatContact]
    {
        guard !ids.isEmpty else { return [] }

        let request = NSFetchRequest<ChatContact>(entityName: ChatContact.EntityName)
        request.predicate = NSPredicate(format: "self IN %@", ids)
        request.returnsObjectsAsFaults = false

        do {
            let fetched = try moc.fetch(request)
            let contactsByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.objectID, $0) })
            return ids.compactMap { contactsByID[$0] }
        } catch let error as NSError {
            NSLog("\(#function) Could not fetch contacts: \(error), \(error.userInfo)")
            return ids.map { moc.object(with: $0) as! ChatContact }
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

        request.propertiesToFetch = [ChatItemsFetcher.objectIDFetchProperty(), "dateNanoseconds"]
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

    // nb of messages added before and after a message matching a search term in search results
    //
    let nbOfMessagesBeforeAfter = 2 // TODO: make this user configurable

    // Upper bound on the number of `index` values packed into one statement
    // when fetching the neighbours of search matches. Each statement costs a
    // near-constant ~15 ms whatever its size (measured on a 200k-message
    // store), so the goal is as few statements as possible; the cap only
    // keeps the SQL bounded for pathological searches.
    private let indexesPerFetch = 5000

    // Outcome of a text search, expressed in object IDs only so it can cross
    // from the worker context to the main one.
    struct SearchResult {
        typealias Group = (contactID: NSManagedObjectID, range: Range<Int>)

        // Messages to display: the matches plus their neighbours, grouped per
        // contact and in conversation order within a contact.
        var messageIDs = [NSManagedObjectID]()
        // Matched contacts, in order of their earliest match (the group order).
        var contactIDs = [NSManagedObjectID]()
        // For each matched contact, the range of `messageIDs` holding its group.
        var groups = [Group]()
    }

    // Finds the messages whose content contains `string` (within the optional
    // date bounds), each accompanied by its `nbOfMessagesBeforeAfter`
    // neighbours in the same conversation. Results are grouped per contact,
    // contacts in order of their earliest match, and in conversation order
    // (`index`) within a contact.
    //
    // Runs on `moc`'s queue. Only object IDs and integer attributes are read
    // from the store: no message body is loaded and no managed object is
    // materialized. In particular the matched contacts' conversations are
    // never loaded as a whole; the neighbours are fetched by `index`, which
    // is assigned contiguously in date order at import time and is indexed.
    func searchChatsForString(_ string:String, inManagedObjectContext moc:NSManagedObjectContext, afterDate:Date? = nil, beforeDate:Date? = nil) -> SearchResult
    {
        // 1. The matches themselves, as (contact, index) pairs, oldest first.
        //    A to-one relationship in a dictionary result comes back as the
        //    related object's ID, which is all the grouping needs.
        let matchRequest = NSFetchRequest<NSDictionary>(entityName: ChatMessage.EntityName)
        matchRequest.resultType = .dictionaryResultType
        matchRequest.propertiesToFetch = [ChatMessage.Attributes.contact.rawValue, ChatMessage.Attributes.index.rawValue]
        matchRequest.sortDescriptors = [NSSortDescriptor(key: ChatMessage.Attributes.dateNanoseconds.rawValue, ascending: true)]

        // [cd]: case- and diacritic-insensitive, so "deja" matches "déjà" and
        // "Deja" alike — matching how the result highlighting in MessagesListView
        // searches the matched text.
        var predicates = [NSPredicate(format: "%K CONTAINS[cd] %@", ChatMessage.Attributes.content.rawValue, string)]
        if let afterDate = afterDate {
            predicates.append(NSPredicate(format: "%K >= %lld", ChatMessage.Attributes.dateNanoseconds.rawValue, ChatItemsFetcher.nanoseconds(from: afterDate)))
        }
        if let beforeDate = beforeDate {
            predicates.append(NSPredicate(format: "%K <= %lld", ChatMessage.Attributes.dateNanoseconds.rawValue, ChatItemsFetcher.nanoseconds(from: beforeDate)))
        }
        matchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        // For every match, the window of indexes to show. Kept as a Set per
        // contact: windows overlap and dedupe naturally, and an index past the
        // end of the conversation simply matches nothing, so no clamping to the
        // conversation length (and no count query) is needed.
        var contactOrder = [NSManagedObjectID]()
        var indexesPerContact = [NSManagedObjectID: Set<Int64>]()
        let window = Int64(nbOfMessagesBeforeAfter)

        do {
            for row in try moc.fetch(matchRequest) {
                guard let contactID = row[ChatMessage.Attributes.contact.rawValue] as? NSManagedObjectID,
                      let index = row[ChatMessage.Attributes.index.rawValue] as? Int64 else { continue }

                if indexesPerContact[contactID] == nil {
                    contactOrder.append(contactID)
                    indexesPerContact[contactID] = []
                }
                indexesPerContact[contactID]!.formUnion(max(index - window, 0) ... index + window)
            }
        } catch let error as NSError {
            NSLog("\(#function) Could not fetch matches for \"\(string)\": \(error), \(error.userInfo)")
            return SearchResult()
        }

        // 2. Fetch exactly those messages, then lay them out per contact,
        //    recording where each contact's group starts and ends.
        let idsPerContact = surroundingMessageIDs(indexesPerContact: indexesPerContact, contactOrder: contactOrder, in: moc)

        var result = SearchResult()
        result.contactIDs = contactOrder
        for contactID in contactOrder {
            let groupStart = result.messageIDs.count
            result.messageIDs.append(contentsOf: idsPerContact[contactID] ?? [])
            result.groups.append((contactID: contactID, range: groupStart ..< result.messageIDs.count))
        }

        return result
    }

    // Object IDs of the messages at the given indexes, keyed by contact, each
    // list in index order.
    //
    // One statement per contact costs about the same ~15 ms whether it uses
    // IN, BETWEEN ranges or a min...max span, so a search hitting 200
    // contacts spent seconds in round trips. Instead the (contact, indexes)
    // pairs are packed into as few statements as possible, as an OR of
    // `contact == X AND index IN {...}` terms, fetched as
    // (objectID, contact, index) dictionaries and regrouped in memory. A
    // contact's indexes may be split across statements; the final per-contact
    // sort by index makes that irrelevant.
    private func surroundingMessageIDs(indexesPerContact: [NSManagedObjectID: Set<Int64>], contactOrder: [NSManagedObjectID], in moc: NSManagedObjectContext) -> [NSManagedObjectID: [NSManagedObjectID]]
    {
        let contactKey = ChatMessage.Attributes.contact.rawValue
        let indexKey = ChatMessage.Attributes.index.rawValue

        var rowsPerContact = [NSManagedObjectID: [(index: Int64, objectID: NSManagedObjectID)]]()

        var terms = [NSPredicate]()
        var termsIndexCount = 0

        func flush() {
            guard !terms.isEmpty else { return }

            let request = NSFetchRequest<NSDictionary>(entityName: ChatMessage.EntityName)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = [ChatItemsFetcher.objectIDFetchProperty(), contactKey, indexKey]
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: terms)

            do {
                for row in try moc.fetch(request) {
                    guard let contactID = row[contactKey] as? NSManagedObjectID,
                          let index = row[indexKey] as? Int64,
                          let objectID = row["objectID"] as? NSManagedObjectID else { continue }
                    rowsPerContact[contactID, default: []].append((index, objectID))
                }
            } catch let error as NSError {
                NSLog("\(#function) Could not fetch surrounding messages: \(error), \(error.userInfo)")
            }

            terms.removeAll()
            termsIndexCount = 0
        }

        for contactID in contactOrder {
            let indexes = indexesPerContact[contactID]!.sorted()

            var chunkStart = 0
            while chunkStart < indexes.count {
                let chunkEnd = min(chunkStart + indexesPerFetch, indexes.count)
                if termsIndexCount + (chunkEnd - chunkStart) > indexesPerFetch {
                    flush()
                }
                let chunk = indexes[chunkStart ..< chunkEnd].map { NSNumber(value: $0) }
                terms.append(NSPredicate(format: "%K == %@ AND %K IN %@", contactKey, contactID, indexKey, chunk))
                termsIndexCount += chunkEnd - chunkStart
                chunkStart = chunkEnd
            }
        }
        flush()

        return rowsPerContact.mapValues { rows in
            rows.sorted { $0.index < $1.index }.map { $0.objectID }
        }
    }

    // A fetch property that yields the row's NSManagedObjectID under the key
    // "objectID" in dictionary results.
    private static func objectIDFetchProperty() -> NSExpressionDescription {
        let property = NSExpressionDescription()
        property.name = "objectID"
        property.expression = NSExpression.expressionForEvaluatedObject()
        property.expressionResultType = .objectIDAttributeType
        return property
    }

}
