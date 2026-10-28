//
//  ContentView.swift
//  MessagesHistoryBrowser
//
//  Main three-column layout view
//

import SwiftUI
import CoreData


struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ContentViewModel()

    // The selection lives in the view model (see ContentViewModel.selectedContact)
    // so a re-import can clear it before the store is emptied.

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar: Contact list
            ContactListView(
                selectedContact: $viewModel.selectedContact,
                viewModel: viewModel
            )
            .frame(width: 250)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Middle: Messages list — search results span all contacts,
            // otherwise show the selected contact's conversation.
            if viewModel.searchTerm.count >= ContentViewModel.searchCountLimit {
                SearchResultsView(viewModel: viewModel)
                    .frame(minWidth: 300)
            } else if let contact = viewModel.selectedContact {
                // Conversation, with its collapsible activity calendar below.
                VStack(spacing: 0) {
                    MessagesListView(
                        contact: contact,
                        viewModel: viewModel
                    )
                    ConversationCalendarPane(viewModel: viewModel)
                }
                .frame(minWidth: 300)
            } else {
                VStack {
                    if !viewModel.isImporting {
                        Text("Select a contact to view messages")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Right: Attachments
            AttachmentsView(viewModel: viewModel)
                .frame(width: 300)
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
                // The observer is owned by the view model for the whole import,
                // so re-evaluating this body does not re-subscribe to the Progress.
                if viewModel.isImporting, let progressObserver = viewModel.importProgressObserver {
                    ImportProgressView(progressWrapper: progressObserver)
                }
            }
        )
        .onAppear {
            viewModel.setupDatabase(appState: appState)
        }
        // Shown after an import if Contacts access wasn't available, so chat
        // participants showing as raw phone numbers/emails has an explanation
        // and a way to fix it, instead of failing silently.
        .alert("Contacts Access Needed", isPresented: $appState.contactsAccessDenied) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("MessagesHistoryBrowser couldn't access your Contacts, so chat participants are shown by phone number or email address instead of name. Grant access in System Settings > Privacy & Security > Contacts, then choose Refresh Chat History.")
        }
        // While searching, selecting a contact narrows the results to it
        // (and deselecting returns to all matches).
        .onChange(of: viewModel.selectedContact) { _, newContact in
            if viewModel.searchTerm.count >= ContentViewModel.searchCountLimit {
                viewModel.narrowSearch(to: newContact)
            }
        }
        // A bar was clicked in a stats window: show that time in the conversation.
        .onChange(of: appState.conversationDateRequest) { _, request in
            guard let request = request else { return }
            appState.conversationDateRequest = nil
            showConversation(for: request)
        }
        // Publish focused values so the menu bar commands can reach the app state
        // and trigger a refresh that actually reloads the visible contact list.
        .focusedSceneValue(\.appState, appState)
        .focusedSceneValue(\.refreshChatHistory) {
            Task { await viewModel.refreshChatHistory(appState: appState) }
        }
        .focusedSceneValue(\.selectedContact, viewModel.selectedContact)
        // Publish the selected contact (only when one is selected) so the
        // Export/Save menu commands can enable and act on it.
//        .modifier(SelectedContactFocusValue(contact: selectedContact))
    }

    // Resolves the request's contact in the main context (it may have been
    // deleted by a re-import since the stats window was opened).
    private func showConversation(for request: ConversationDateRequest) {
        let context = MOCController.sharedInstance.managedObjectContext
        guard let contactID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: request.contactURI),
              let contact = try? context.existingObject(with: contactID) as? ChatContact else { return }

        viewModel.showInConversation(contact, at: request.date)
    }
}

// Publishes the selected contact as a focused value only when non-nil, so the
// menu commands' `.disabled(selectedContact == nil)` reflects the real selection.

//struct SelectedContactFocusValue: ViewModifier {
//    let contact: ChatContact?
//
//    func body(content: Content) -> some View {
//        if let contact = contact {
//            content.focusedSceneValue(\.selectedContact, contact)
//        } else {
//            content
//        }
//    }
//}
