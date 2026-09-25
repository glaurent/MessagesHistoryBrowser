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

    @State private var showFilters = false

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
                // A popover rather than a Menu: on macOS a Menu is an NSMenu,
                // which can't host a DatePicker (it renders as an inert,
                // greyed-out item). The icon fills in while a date bound is active.
                Button {
                    showFilters.toggle()
                } label: {
                    Image(systemName: viewModel.isDateFilterActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .help("Filter contacts and messages")
                .popover(isPresented: $showFilters, arrowEdge: .bottom) {
                    FilterPopoverView(viewModel: viewModel)
                }
            }
        }
        // Re-run the current query whenever a date bound or its toggle changes.
        .onChange(of: viewModel.afterDateEnabled) { viewModel.applyDateFilter() }
        .onChange(of: viewModel.beforeDateEnabled) { viewModel.applyDateFilter() }
        .onChange(of: viewModel.afterDate) {
            if viewModel.afterDateEnabled { viewModel.applyDateFilter() }
        }
        .onChange(of: viewModel.beforeDate) {
            if viewModel.beforeDateEnabled { viewModel.applyDateFilter() }
        }
    }
}

// Contents of the filter popover: the unknown-contacts toggle plus the two
// optional date bounds, each with its own enable switch.
struct FilterPopoverView: View {
    @ObservedObject var viewModel: ContentViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show Unknown Contacts", isOn: $appState.showChatsFromUnknown)

            Divider()

            Text("Date Range")
                .font(.headline)

            HStack {
                Toggle("After", isOn: $viewModel.afterDateEnabled)
                Spacer()
                DatePicker("After date", selection: $viewModel.afterDate, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!viewModel.afterDateEnabled)
            }

            HStack {
                Toggle("Before", isOn: $viewModel.beforeDateEnabled)
                Spacer()
                DatePicker("Before date", selection: $viewModel.beforeDate, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!viewModel.beforeDateEnabled)
            }
        }
        .padding()
        .frame(width: 280)
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
