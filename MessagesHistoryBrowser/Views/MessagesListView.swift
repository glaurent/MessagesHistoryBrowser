//
//  MessagesListView.swift
//  MessagesHistoryBrowser
//
//  Messages display view
//

import SwiftUI

struct MessagesListView: View {
    let contact: ChatContact
    @ObservedObject var viewModel: ContentViewModel

    @State private var highlightTerm: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.currentMessages, id: \.objectID) { item in
                        if let message = item as? ChatMessage {
                            MessageBubbleView(
                                message: message,
                                highlightTerm: highlightTerm,
                                showDetailedSender: viewModel.isSearchActive
                            )
                        } else if let attachment = item as? ChatAttachment {
                            AttachmentInlineView(attachment: attachment)
                        }
                    }
                }
                .padding()
            }
            .modifier(ConversationScrollTargetModifier(viewModel: viewModel, proxy: proxy))
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
        // Only highlight once a search is actually running (isSearchActive,
        // 3+ characters) — this view keeps showing the full, unfiltered
        // conversation below that threshold, so highlighting a 1- or
        // 2-character term here would scan and re-render every visible bubble
        // for a "search" that never happened.
        .onReceive(viewModel.$searchTerm) { newValue in
            highlightTerm = viewModel.isSearchActive ? newValue : nil
        }
    }

    // Go through the view model so the current date bounds are applied.
    private func loadMessages(for contact: ChatContact) {
        viewModel.loadMessagesForContact(contact)
    }
}

// Shows search matches, which span multiple contacts. Reads the same
// @Published results the fetcher's completion (owned by ContentViewModel) fills.
struct SearchResultsView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        ScrollViewReader { proxy in
            searchResultsScrollView
                .modifier(ConversationScrollTargetModifier(viewModel: viewModel, proxy: proxy))
        }
        .navigationTitle("Search Results")
    }

    private var searchResultsScrollView: some View {
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
                    ForEach(viewModel.currentMessages, id: \.objectID) { item in
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

                    // Only the first page of a large match set is published
                    // for display (see ContentViewModel.searchResultPageSize);
                    // this reveals more without re-running the search.
                    if viewModel.displayedSearchMatchCount < viewModel.totalSearchMatchCount {
                        VStack(spacing: 8) {
                            Text("Showing \(viewModel.displayedSearchMatchCount) of \(viewModel.totalSearchMatchCount) matches")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Show More") {
                                viewModel.showMoreSearchResults()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                .padding()
            }
        }
    }
}

// Scrolls to viewModel.conversationScrollTarget ("Show in Conversation" in the
// attachments grid). When the target's contact was just selected, its
// conversation is still loading, so this also retries whenever
// currentMessages changes, and clears the target once it has scrolled.
struct ConversationScrollTargetModifier: ViewModifier {
    @ObservedObject var viewModel: ContentViewModel
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            .onAppear {
                scrollToTargetIfLoaded()
            }
            .onChange(of: viewModel.conversationScrollTarget) { _ in
                scrollToTargetIfLoaded()
            }
            .onChange(of: viewModel.currentMessages) { _ in
                scrollToTargetIfLoaded()
            }
    }

    private func scrollToTargetIfLoaded() {
        guard let target = viewModel.conversationScrollTarget,
              viewModel.currentMessages.contains(where: { $0.objectID == target }) else { return }

        viewModel.conversationScrollTarget = nil
        // Deferred one run-loop turn so a just-published currentMessages has
        // been laid out before scrolling to one of its rows.
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }
}

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

                    Text(message.date.formatted(date: .abbreviated, time: .shortened))
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

    // Builds a Text by concatenating segments, styling case- and diacritic-
    // insensitive matches of `term` (bold + color) — the same comparison the
    // ChatItemsFetcher search predicate (CONTAINS[cd]) uses to find these
    // messages, so every reported match actually gets highlighted here.
    private func highlightedText(for content: String, term: String?) -> Text {
        guard let term = term, !term.isEmpty else { return Text(content) }

        var result = Text("")
        let ns = content as NSString
        var searchRange = NSRange(location: 0, length: ns.length)

        while searchRange.location < ns.length {
            let match = ns.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
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

struct AttachmentInlineView: View {
    let attachment: ChatAttachment
    @State private var image: NSImage?
    @Environment(\.displayScale) private var displayScale

    // Largest size the inline image is shown at, in points.
    private static let maxSide: CGFloat = 300

    var body: some View {
        HStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: AttachmentInlineView.maxSide, maxHeight: AttachmentInlineView.maxSide)
                    .cornerRadius(8)
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.secondary)
            }
        }
        // Decoded off the main thread at display size and cached; cancelled if
        // the row scrolls away before its decode has started.
        .task(id: attachment.objectID) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let fileName = attachment.fileName else { return }
        let path = fileName.standardizingPath()

        let maxPixelSize = Int((AttachmentInlineView.maxSide * displayScale).rounded(.up))
        image = await AttachmentThumbnailCache.shared.thumbnail(forFileAt: path, maxPixelSize: maxPixelSize)
    }
}

// String extension moved to a shared location to avoid conflicts
