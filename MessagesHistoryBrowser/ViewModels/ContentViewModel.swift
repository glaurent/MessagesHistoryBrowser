    //
    //  ContentViewModel.swift
    //  MessagesHistoryBrowser
    //
    //  Created by Guillaume Laurent on 25/09/2026.
    //  Copyright © 2026 Guillaume Laurent. All rights reserved.
    //

import Foundation
import CoreData

    // View Model for Content View

@MainActor
class ContentViewModel: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {

    @Published var searchTerm: String = ""
    @Published var isImporting = false
    @Published var importProgress = Progress(totalUnitCount: 10)

    // Observable, rate-limited mirror of importProgress for the overlay.
    // Created once per import so the view keeps a single KVO subscription
    // instead of re-creating one on every re-render of ContentView.
    @Published private(set) var importProgressObserver: ObservableProgress?

    @Published var allKnownContacts: [ChatContact] = []
    @Published var allUnknownContacts: [ChatContact] = []
    @Published var searchedContacts: [ChatContact]?

        // Live contact list, kept up to date by an NSFetchedResultsController.
    private var contactsController: NSFetchedResultsController<ChatContact>?

    @Published var currentMessages: [ChatItem] = []
    @Published var currentAttachments: [ChatAttachment] = []

    // A common search term can match tens of thousands of messages (a bare
    // " a " matched ~79,000 in one real store). SwiftUI's ForEach diffs the
    // whole currentMessages array on every change, so handing it that many
    // rows at once makes typing in the search field stutter. Only a bounded
    // prefix is published for display; totalSearchMatchCount lets the view
    // show "N of M" and offer "Show More", which just reveals more of
    // allSearchMatchingItems — already fully computed by ChatItemsFetcher —
    // rather than re-running the search.
    static let searchCountLimit = 1
    private static let searchResultPageSize = 500
    private var allSearchMatchingItems: [ChatItem] = []
    @Published private(set) var totalSearchMatchCount = 0
    @Published private(set) var displayedSearchMatchCount = 0

    // The contact selected in the sidebar. Owned here rather than as view
    // state so a re-import can clear it synchronously, before the store is
    // emptied and the selected object becomes a deleted one.
    @Published var selectedContact: ChatContact? {
        didSet {
            guard oldValue != selectedContact else { return }
            focusedDay = nil
            pendingScrollDate = nil
        }
    }

    // Item the messages list should scroll to, set by "Show in Conversation"
    // in the attachments grid. The list scrolls once the item is among
    // currentMessages (it may still be loading), then clears this.
    @Published var conversationScrollTarget: NSManagedObjectID?

    // Day highlighted in the conversation calendar (start of day), set by
    // clicking a calendar day or a bar in the stats window. The calendar
    // scrolls to its month when it changes.
    @Published var focusedDay: Date?

    // Date to scroll the conversation to once the selected contact's
    // messages have loaded (see showInConversation(_:at:)).
    private var pendingScrollDate: Date?

    @Published var beforeDateEnabled = false
    @Published var afterDateEnabled = false
    @Published var beforeDate = Date().addingTimeInterval(3600 * 24 * -7) // a week ago
    @Published var afterDate = Date().addingTimeInterval(3600 * 24 * -30) // a month ago

    // True when the search field holds enough characters to be in search mode.
    var isSearchActive: Bool { searchTerm.count >= Self.searchCountLimit }

    var isDateFilterActive: Bool { afterDateEnabled || beforeDateEnabled }

    // Effective date bounds handed to the fetcher (nil when the corresponding
    // toggle is off). Both bounds include the whole selected day, whatever time
    // component the DatePicker's Date happens to carry.
    var effectiveAfterDate: Date? {
        guard afterDateEnabled else { return nil }
        return Calendar.current.startOfDay(for: afterDate)
    }

    var effectiveBeforeDate: Date? {
        guard beforeDateEnabled else { return nil }
        let startOfDay = Calendar.current.startOfDay(for: beforeDate)
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)
    }

    // Set by applyDateFilter() when a search narrowed to one contact must be
    // re-run; the fetcher completion re-applies the narrowing to the new results.
    private var contactToRenarrow: ChatContact?

    var setupDBSucceeded = false

    override init() {
        super.init()
    }

    func setupDatabase(appState: AppState) {
        setupFetcherCallback()
        setupContactsController()

        let moc = MOCController.sharedInstance.managedObjectContext

        if Chat.numberOfChatsInContext(moc) == 0 {
            Task {
                await importMessagesFromOSXApp(appState: appState)
            }
        } else if appState.needDBReload {
            Task {
                await refreshChatHistory(appState: appState)
            }
        } else {
            loadContacts()
        }
    }

        // Sets up the NSFetchedResultsController that drives the contact list. It
        // observes the main viewContext, which merges the background import's saves
        // (see automaticallyMergesChangesFromParent), so the list updates live.
    private func setupContactsController() {
        guard contactsController == nil else { return }

        let context = MOCController.sharedInstance.managedObjectContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        let request = NSFetchRequest<ChatContact>(entityName: "Contact")
        request.predicate = NSPredicate(format: "messages.@count > 0")
        request.sortDescriptors = [ChatContact.sortDescriptor]

        let controller = NSFetchedResultsController(fetchRequest: request,
                                                    managedObjectContext: context,
                                                    sectionNameKeyPath: nil,
                                                    cacheName: nil)
        controller.delegate = self
        contactsController = controller

        loadContacts()
    }

        // Re-fetches and republishes the contact list. The FRC delegate keeps it
        // current for incremental changes; this is also called after import/refresh
        // to reconcile batch deletes (which don't emit change notifications).
    func loadContacts() {
        try? contactsController?.performFetch()
        updateContactArrays()
    }

    private func updateContactArrays() {
        let all = contactsController?.fetchedObjects ?? []

        // Single pass instead of two separate filter() calls over `all`.
        // Order matters (the fetch request sorts by name) and a plain loop
        // preserves it, unlike Array.partition(by:), which doesn't guarantee
        // stable ordering within each side.
        var known = [ChatContact]()
        var unknown = [ChatContact]()
        known.reserveCapacity(all.count)
        unknown.reserveCapacity(all.count)
        for contact in all {
            if contact.known {
                known.append(contact)
            } else {
                unknown.append(contact)
            }
        }
        allKnownContacts = known
        allUnknownContacts = unknown
    }

    nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        Task { @MainActor in
            self.updateContactArrays()
        }
    }

    func importMessagesFromOSXApp(appState: AppState) async {
        guard let chatsDatabase = appState.chatsDatabase else { return }

        isImporting = true
        importProgress = Progress(totalUnitCount: 10)
        importProgressObserver = ObservableProgress(progress: importProgress)

        let contactsAccessGranted = await chatsDatabase.populate(importProgress)
        reportContactsAccessResult(contactsAccessGranted, appState: appState)

        isImporting = false
        importProgressObserver = nil
        loadContacts()
    }

    func refreshChatHistory(appState: AppState) async {
        guard let chatsDatabase = appState.chatsDatabase else { return }

        // Everything the UI shows is about to be deleted from the store. Drop
        // every reference first, synchronously, so the next render has nothing
        // left that could fault a deleted object.
        discardDisplayedData()

        appState.isRefreshingHistory = true
        isImporting = true
        importProgress = Progress(totalUnitCount: 10)
        importProgressObserver = ObservableProgress(progress: importProgress)

        MOCController.sharedInstance.clearAllCoreData()
        let contactsAccessGranted = await chatsDatabase.populate(importProgress)
        reportContactsAccessResult(contactsAccessGranted, appState: appState)

        isImporting = false
        importProgressObserver = nil
        loadContacts()
        appState.isRefreshingHistory = false
    }

    // Surfaces a failed Contacts lookup to the user and makes sure the import
    // is actually visible. Without Contacts access every chat resolves to an
    // "unknown" contact (no name, no identifier) — and the sidebar hides
    // unknown contacts by default, so without this the whole app would appear
    // empty after the user dismisses the alert, with no clue that the chats
    // are there, just filtered out.
    private func reportContactsAccessResult(_ granted: Bool, appState: AppState) {
        appState.contactsAccessDenied = !granted
        if !granted {
            appState.showChatsFromUnknown = true
        }
    }

    // Forgets every store object held for display: selection, contact lists,
    // messages, attachments, search state, and the fetcher's cached results.
    // The contact lists come back as the import saves (via the fetched results
    // controller) and are reconciled by loadContacts() when it finishes.
    private func discardDisplayedData() {
        selectedContact = nil
        searchTerm = ""
        contactToRenarrow = nil
        searchedContacts = nil
        allKnownContacts.removeAll()
        allUnknownContacts.removeAll()
        currentMessages.removeAll()
        currentAttachments.removeAll()
        clearSearchResultPaging()
        ChatItemsFetcher.sharedInstance.reset()
    }

    fileprivate func clearSearchResultPaging() {
        allSearchMatchingItems.removeAll()
        totalSearchMatchCount = 0
        displayedSearchMatchCount = 0
    }

    func loadMessagesForContact(_ contact: ChatContact) {
        syncDateFilterToFetcher()
        ChatItemsFetcher.sharedInstance.contact = contact
        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
    }

    private func syncDateFilterToFetcher() {
        ChatItemsFetcher.sharedInstance.afterDate = effectiveAfterDate
        ChatItemsFetcher.sharedInstance.beforeDate = effectiveBeforeDate
    }

    // Re-runs whatever is currently displayed (search results or the selected
    // contact's conversation) with the current date bounds.
    func applyDateFilter() {
        syncDateFilterToFetcher()
        let fetcher = ChatItemsFetcher.sharedInstance

        if isSearchActive {
            // The bounds are applied by the search fetch itself, so the whole
            // search has to be re-run. Remember any narrowing so the completion
            // can restore it once the new results arrive.
            contactToRenarrow = fetcher.contact
            performSearch()
        } else if fetcher.contact != nil {
            fetcher.searchWithCompletionBlock()
        }
    }

        // Single owner of the fetcher's completion, set once at launch so search
        // results reach the UI whether or not a contact is (or ever was) selected.
        //
        // ChatItemsFetcher always invokes this on the main queue already —
        // directly, for its synchronous narrow/clear path, or via its own
        // DispatchQueue.main.async for the two async (search/browse) paths —
        // so hopping through another DispatchQueue.main.async here would only
        // add a second, needless run-loop turn before every result reaches
        // the UI. MainActor.assumeIsolated documents and asserts that
        // guarantee instead of re-dispatching on top of it.
    fileprivate func setupFetcherCallback() {
        ChatItemsFetcher.sharedInstance.completion = { [weak self] items, attachments, matchedContacts in
            MainActor.assumeIsolated {
                guard let self = self else { return }

                // Every completion call is a genuinely new result set (Show
                // More never goes through the fetcher — see
                // showMoreSearchResults()), so paging always resets here,
                // whether this is a new search, a narrow-to-contact, or a
                // date-filter re-run.
                if self.isSearchActive {
                    self.allSearchMatchingItems = items
                    self.totalSearchMatchCount = items.count
                    self.displayedSearchMatchCount = min(items.count, Self.searchResultPageSize)
                    self.currentMessages = Array(items.prefix(self.displayedSearchMatchCount))
                } else {
                    self.clearSearchResultPaging()
                    self.currentMessages = items
                    // A date was requested before this conversation loaded.
                    if let date = self.pendingScrollDate,
                       ChatItemsFetcher.sharedInstance.contact == self.selectedContact {
                        self.pendingScrollDate = nil
                        self.scrollToFirstItem(onOrAfter: date)
                    }
                }
                self.currentAttachments = attachments
                    // Only a search populates matchedContacts; use it to filter the sidebar.
                if let matchedContacts = matchedContacts {
                    self.searchedContacts = matchedContacts
                }
                    // A date-filter change re-ran a narrowed search: narrow again.
                if let contact = self.contactToRenarrow {
                    self.contactToRenarrow = nil
                    self.narrowSearch(to: contact)
                }
            }
        }
    }

        // Reveals more of the already-fetched search results. No new search
        // runs: ChatItemsFetcher already computed the full ordered list, so
        // this is just extending how much of it is published for display.
    func showMoreSearchResults() {
        displayedSearchMatchCount = min(displayedSearchMatchCount + Self.searchResultPageSize, allSearchMatchingItems.count)
        currentMessages = Array(allSearchMatchingItems.prefix(displayedSearchMatchCount))
    }

        // While a search is active, restrict the results to a single contact (or
        // back to all matches when contact is nil). Relies on the fetcher's
        // contact + searchTerm path, which filters the cached full result set.
    func narrowSearch(to contact: ChatContact?) {
        ChatItemsFetcher.sharedInstance.contact = contact
        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
    }

        // Scrolls the conversation to where the attachment was sent. Outside
        // of a search, the attachment's contact is selected first if needed,
        // so its conversation gets loaded.
    func showInConversation(_ attachment: ChatAttachment) {
        if !isSearchActive && selectedContact != attachment.contact {
            selectedContact = attachment.contact
        }
        conversationScrollTarget = attachment.objectID
    }

        // Shows the contact's conversation from `date` onwards (a bar clicked
        // in the stats window). Leaves search mode, since the conversation
        // and its calendar aren't shown during a search. If the conversation
        // isn't the one loaded yet, the scroll happens once it has loaded.
    func showInConversation(_ contact: ChatContact, at date: Date) {
        let wasSearching = isSearchActive
        if wasSearching {
            // Reset the fetcher's search term now, rather than waiting for the
            // search field's onChange, so the conversation load below can't
            // be served from the cached search results.
            searchTerm = ""
            performSearch()
        }

        if wasSearching || selectedContact != contact {
            // Set after selectedContact, whose didSet clears it.
            selectedContact = contact
            pendingScrollDate = date
        } else {
            scrollToFirstItem(onOrAfter: date)
        }
    }

        // Scrolls the conversation (and the calendar) to the first displayed
        // item on or after `date` — or the last item, if every displayed item
        // is older (e.g. a date filter excludes later messages).
    private func scrollToFirstItem(onOrAfter date: Date) {
        guard let item = currentMessages.first(where: { $0.date >= date }) ?? currentMessages.last else { return }
        focusedDay = Calendar.current.startOfDay(for: item.date)
        conversationScrollTarget = item.objectID
    }

    func performSearch() {
        guard isSearchActive else {
                // Search cleared / too short: leave search mode and reset the fetcher.
            searchedContacts = nil
            currentMessages = []
            currentAttachments = []
            clearSearchResultPaging()
            ChatItemsFetcher.sharedInstance.searchTerm = nil
            return
        }

        syncDateFilterToFetcher()
        ChatItemsFetcher.sharedInstance.contact = nil
        ChatItemsFetcher.sharedInstance.searchTerm = searchTerm
        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
    }
}
