//
//  MessagesListView.swift
//  MessagesHistoryBrowser
//
//  Messages display view
//

import SwiftUI

@available(macOS 11.0, *)
struct MessagesListView: View {
    let contact: ChatContact
    @ObservedObject var viewModel: ContentViewModel

    @State private var highlightTerm: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(viewModel.currentMessages.enumerated()), id: \.element.objectID) { index, item in
                    if let message = item as? ChatMessage {
                        MessageBubbleView(
                            message: message,
                            highlightTerm: highlightTerm,
                            showDetailedSender: viewModel.searchTerm.isEmpty ? false : true
                        )
                    } else if let attachment = item as? ChatAttachment {
                        AttachmentInlineView(attachment: attachment)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(contact.name)
        .onAppear {
            loadMessages(for: contact)
        }
        // The view is reused across selections (only `contact` changes), so
        // reload explicitly when it does. Use the new value from the closure —
        // reading self.contact here can yield the previous selection.
        .onChange(of: contact) { newContact in
            loadMessages(for: newContact)
        }
        .onReceive(viewModel.$searchTerm) { newValue in
            highlightTerm = newValue.isEmpty ? nil : newValue
        }
    }

    private func loadMessages(for contact: ChatContact) {
        ChatItemsFetcher.sharedInstance.contact = contact
        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
    }
}

// Shows search matches, which span multiple contacts. Reads the same
// @Published results the fetcher's completion (owned by ContentViewModel) fills.
@available(macOS 11.0, *)
struct SearchResultsView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        ScrollView {
            if viewModel.currentMessages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No matches for “\(viewModel.searchTerm)”")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(viewModel.currentMessages.enumerated()), id: \.element.objectID) { _, item in
                        if let message = item as? ChatMessage {
                            MessageBubbleView(
                                message: message,
                                highlightTerm: viewModel.searchTerm,
                                showDetailedSender: true
                            )
                        } else if let attachment = item as? ChatAttachment {
                            AttachmentInlineView(attachment: attachment)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Search Results")
    }
}

@available(macOS 11.0, *)
struct MessageBubbleView: View {
    let message: ChatMessage
    let highlightTerm: String?
    let showDetailedSender: Bool

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
            if showDetailedSender {
                Text(message.contact.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                if message.isFromMe {
                    Spacer(minLength: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Message text, with any search term matches highlighted.
                    highlightedText(for: message.content ?? "", term: highlightTerm)

                    Text(message.date, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(message.isFromMe ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                )

                if !message.isFromMe {
                    Spacer(minLength: 60)
                }
            }
        }
    }

    // Builds a Text by concatenating segments, styling case-insensitive matches
    // of `term`. Uses Text composition (bold + color) so it works on macOS 11.
    private func highlightedText(for content: String, term: String?) -> Text {
        guard let term = term, !term.isEmpty else { return Text(content) }

        var result = Text("")
        let ns = content as NSString
        var searchRange = NSRange(location: 0, length: ns.length)

        while searchRange.location < ns.length {
            let match = ns.range(of: term, options: .caseInsensitive, range: searchRange)
            if match.location == NSNotFound {
                result = result + Text(ns.substring(with: searchRange))
                break
            }

            if match.location > searchRange.location {
                let preRange = NSRange(location: searchRange.location, length: match.location - searchRange.location)
                result = result + Text(ns.substring(with: preRange))
            }

            result = result + Text(ns.substring(with: match))
                .bold()
                .foregroundColor(.orange)

            let next = match.location + match.length
            searchRange = NSRange(location: next, length: ns.length - next)
        }

        return result
    }
}

@available(macOS 11.0, *)
struct AttachmentInlineView: View {
    let attachment: ChatAttachment
    @State private var image: NSImage?
    
    var body: some View {
        HStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 300)
                    .cornerRadius(8)
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let fileName = attachment.fileName else { return }
        let path = fileName.standardizingPath()
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let loadedImage = NSImage(contentsOfFile: path) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                }
            }
        }
    }
}

// String extension moved to a shared location to avoid conflicts
