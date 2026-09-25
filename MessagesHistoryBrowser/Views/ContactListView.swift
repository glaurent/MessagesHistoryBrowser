//
//  ContactListView.swift
//  MessagesHistoryBrowser
//
//  Contact list sidebar view
//

import SwiftUI
import Contacts
import Combine


struct ContactListView: View {
    @Binding var selectedContact: ChatContact?
    @ObservedObject var viewModel: ContentViewModel
    @EnvironmentObject var appState: AppState

    var filteredContacts: [ChatContact] {
        if let searchedContacts = viewModel.searchedContacts {
            return searchedContacts
        }
        
        if appState.showChatsFromUnknown {
            return viewModel.allKnownContacts + viewModel.allUnknownContacts
        }
        
        return viewModel.allKnownContacts
    }
    
    var body: some View {
        List(selection: $selectedContact) {
            ForEach(filteredContacts, id: \.self) { contact in
                ContactRow(contact: contact)
                    .tag(contact)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    // Bind directly to the view model so the field and clear button
                    // always reflect the actual search state (single source of truth).
                    TextField("Search messages", text: $viewModel.searchTerm)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    if !viewModel.searchTerm.isEmpty {
                        Button {
                            viewModel.searchTerm = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Clear search")
                    }
                }
            }
        }
        // performSearch handles both the search (>= 3 chars) and the
        // clear/too-short cases (resetting search state).
        .onChange(of: viewModel.searchTerm) { _ in
            viewModel.performSearch()
        }
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Show Unknown Contacts", isOn: $appState.showChatsFromUnknown)
                    
                    Divider()
                    
                    DatePicker(
                        "After Date",
                        selection: $viewModel.afterDate,
                        displayedComponents: .date
                    )
                    
                    DatePicker(
                        "Before Date",
                        selection: $viewModel.beforeDate,
                        displayedComponents: .date
                    )
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}


struct ContactRow: View {
    let contact: ChatContact
    @State private var contactImage: NSImage?
    @State private var initials: String = ""
    
    var body: some View {
        HStack(spacing: 12) {
            // Contact avatar
            Group {
                if let image = contactImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if !initials.isEmpty {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.2))
                        Text(initials)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            
            Text(contact.name)
                .lineLimit(1)
        }
        .onAppear {
            loadContactImage()
        }
    }
    
    private func loadContactImage() {
        let (image, initialsPair) = ContactsMap.sharedInstance.contactImage(contact.identifier)
        
        if let image = image {
            contactImage = roundCorners(image)
        } else if let initialsPair = initialsPair {
            initials = "\(initialsPair.0)\(initialsPair.1)"
        }
    }
}

// roundCorners function is in RoundImage.swift
