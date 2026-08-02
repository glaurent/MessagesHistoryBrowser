//
//  ContentView.swift
//  MessagesHistoryBrowser
//
//  Main three-column layout view
//

import SwiftUI

@available(macOS 11.0, *)
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ContentViewModel()
    
    @State private var selectedContact: ChatContact?
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar: Contact list
                ContactListView(
                    selectedContact: $selectedContact,
                    viewModel: viewModel
                )
                .frame(width: 250)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Middle: Messages list — search results span all contacts,
                // otherwise show the selected contact's conversation.
                if viewModel.searchTerm.count >= 3 {
                    SearchResultsView(viewModel: viewModel)
                        .frame(minWidth: 300)
                } else if let contact = selectedContact {
                    MessagesListView(
                        contact: contact,
                        viewModel: viewModel
                    )
                    .frame(minWidth: 300)
                } else {
                    VStack {
                        Text("Select a contact to view messages")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Divider()
                
                // Right: Attachments
                AttachmentsView(viewModel: viewModel)
                    .frame(width: 300)
            }
        }
        .navigationTitle("Messages History Browser")
        .toolbar {
            ToolbarItemGroup {
                if appState.isRefreshingHistory {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 8)
                }
            }
        }
        .background(
            Group {
                if viewModel.isImporting {
                    ImportProgressView(progressWrapper: ObservableProgress(progress: viewModel.importProgress))
                }
            }
        )
        .onAppear {
            viewModel.setupDatabase(appState: appState)
        }
        // While searching, selecting a contact narrows the results to it
        // (and deselecting returns to all matches).
        .onChange(of: selectedContact) { newContact in
            if viewModel.searchTerm.count >= 3 {
                viewModel.narrowSearch(to: newContact)
            }
        }
        // Publish focused values so the menu bar commands can reach the app state
        // and trigger a refresh that actually reloads the visible contact list.
        .focusedValue(\.appState, appState)
        .focusedValue(\.refreshChatHistory) {
            Task { await viewModel.refreshChatHistory(appState: appState) }
        }
        // Publish the selected contact (only when one is selected) so the
        // Export/Save menu commands can enable and act on it.
        .modifier(SelectedContactFocusValue(contact: selectedContact))
    }
}

// Publishes the selected contact as a focused value only when non-nil, so the
// menu commands' `.disabled(selectedContact == nil)` reflects the real selection.
@available(macOS 11.0, *)
struct SelectedContactFocusValue: ViewModifier {
    let contact: ChatContact?

    func body(content: Content) -> some View {
        if let contact = contact {
            content.focusedValue(\.selectedContact, contact)
        } else {
            content
        }
    }
}

// View Model for Content View
@available(macOS 11.0, *)
@MainActor
class ContentViewModel: ObservableObject {
    @Published var searchTerm: String = ""
    @Published var isImporting = false
    @Published var importProgress = Progress(totalUnitCount: 10)
    
    @Published var allKnownContacts: [ChatContact] = []
    @Published var allUnknownContacts: [ChatContact] = []
    @Published var searchedContacts: [ChatContact]?
    
    @Published var currentMessages: [ChatItem] = []
    @Published var currentAttachments: [ChatAttachment] = []
    
    @Published var beforeDateEnabled = false
    @Published var afterDateEnabled = false
    @Published var beforeDate = Date().addingTimeInterval(3600 * 24 * -7) // a week ago
    @Published var afterDate = Date().addingTimeInterval(3600 * 24 * -30) // a month ago
    
    var setupDBSucceeded = false
    
    func setupDatabase(appState: AppState) {
        setupFetcherCallback()

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
    
    func loadContacts() {
        let moc = MOCController.sharedInstance.managedObjectContext
        allKnownContacts = ChatContact.allKnownContacts(moc)
        allUnknownContacts = ChatContact.allUnknownContacts(moc)
    }
    
    func importMessagesFromOSXApp(appState: AppState) async {
        guard let chatsDatabase = appState.chatsDatabase else { return }
        
        isImporting = true
        importProgress = Progress(totalUnitCount: 10)
        
        await chatsDatabase.populate(importProgress)
        
        isImporting = false
        loadContacts()
    }
    
    func refreshChatHistory(appState: AppState) async {
        guard let chatsDatabase = appState.chatsDatabase else { return }
        
        appState.isRefreshingHistory = true
        isImporting = true
        importProgress = Progress(totalUnitCount: 10)
        
        MOCController.sharedInstance.clearAllCoreData()
        await chatsDatabase.populate(importProgress)
        
        isImporting = false
        loadContacts()
        appState.isRefreshingHistory = false
    }
    
    func loadMessagesForContact(_ contact: ChatContact) {
        ChatItemsFetcher.sharedInstance.contact = contact
        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
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
        guard searchTerm.count >= 3 else {
            // Search cleared / too short: leave search mode and reset the fetcher.
            searchedContacts = nil
            currentMessages = []
            currentAttachments = []
            ChatItemsFetcher.sharedInstance.searchTerm = nil
            return
        }

        ChatItemsFetcher.sharedInstance.contact = nil
        ChatItemsFetcher.sharedInstance.searchTerm = searchTerm
        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
    }
}
