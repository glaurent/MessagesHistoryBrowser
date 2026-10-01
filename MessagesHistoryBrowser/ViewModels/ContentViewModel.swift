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

    // The contact selected in the sidebar. Owned here rather than as view
    // state so a re-import can clear it synchronously, before the store is
    // emptied and the selected object becomes a deleted one.
    @Published var selectedContact: ChatContact?

    @Published var beforeDateEnabled = false
    @Published var afterDateEnabled = false
    @Published var beforeDate = Date().addingTimeInterval(3600 * 24 * -7) // a week ago
    @Published var afterDate = Date().addingTimeInterval(3600 * 24 * -30) // a month ago

    // True when the search field holds enough characters to be in search mode.
    var isSearchActive: Bool { searchTerm.count >= 3 }

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
        allKnownContacts = all.filter { $0.known }
        allUnknownContacts = all.filter { !$0.known }
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
        ChatItemsFetcher.sharedInstance.reset()
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
    private func setupFetcherCallback() {
        ChatItemsFetcher.sharedInstance.completion = { [weak self] items, attachments, matchedContacts in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentMessages = items
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

        // While a search is active, restrict the results to a single contact (or
        // back to all matches when contact is nil). Relies on the fetcher's
        // contact + searchTerm path, which filters the cached full result set.
    func narrowSearch(to contact: ChatContact?) {
        ChatItemsFetcher.sharedInstance.contact = contact
        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
    }

    func performSearch() {
        guard isSearchActive else {
                // Search cleared / too short: leave search mode and reset the fetcher.
            searchedContacts = nil
            currentMessages = []
            currentAttachments = []
            ChatItemsFetcher.sharedInstance.searchTerm = nil
            return
        }

        syncDateFilterToFetcher()
        ChatItemsFetcher.sharedInstance.contact = nil
        ChatItemsFetcher.sharedInstance.searchTerm = searchTerm
        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
    }
}
