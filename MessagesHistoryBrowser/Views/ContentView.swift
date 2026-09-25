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
