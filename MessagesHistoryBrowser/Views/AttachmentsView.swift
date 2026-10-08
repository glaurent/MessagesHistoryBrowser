//
//  AttachmentsView.swift
//  MessagesHistoryBrowser
//
//  Attachments grid view
//

import SwiftUI
import CoreData


struct AttachmentsView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var selectedAttachment: ChatAttachment?

    let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 15)
    ]
    
    var body: some View {
        ScrollView {
            if viewModel.currentAttachments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Attachments")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(viewModel.currentAttachments, id: \.objectID) { attachment in
                        AttachmentThumbnailView(attachment: attachment)
                            .onTapGesture {
                                selectedAttachment = attachment
                            }
                            .contextMenu {
                                Button("Show in Finder") {
                                    showAttachmentInFinder(attachment)
                                }
                            }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Attachments")
        .sheet(item: $selectedAttachment) { attachment in
            ImageViewerSheet(attachments: viewModel.currentAttachments, initialAttachment: attachment)
        }
    }

    private func showAttachmentInFinder(_ attachment: ChatAttachment) {
        guard let fileName = attachment.fileName else { return }
        let path = fileName.standardizingPath()
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}


struct AttachmentThumbnailView: View {
    let attachment: ChatAttachment
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var displayScale

    // Cell size in points; the thumbnail is requested at this size times the
    // display scale, so it is sharp on Retina without decoding more than needed.
    private static let cellSide: CGFloat = 120

    // Shared: DateFormatter creation is expensive and this view is created
    // once per visible cell, every time it scrolls into view.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: AttachmentThumbnailView.cellSide, height: AttachmentThumbnailView.cellSide)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .clipped()

            Text(AttachmentThumbnailView.dateFormatter.string(from: attachment.date))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        // Decoded off the main thread at cell size and cached; cancelled if the
        // cell scrolls away before its decode has started.
        .task(id: attachment.objectID) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let fileName = attachment.fileName else { return }
        let path = fileName.standardizingPath()

        // Attachment still in iCloud, nothing to decode locally.
        if path.hasSuffix(".pluginPayloadAttachment") {
            return
        }

        let maxPixelSize = Int((AttachmentThumbnailView.cellSide * displayScale).rounded(.up))
        thumbnail = await AttachmentThumbnailCache.shared.thumbnail(forFileAt: path, maxPixelSize: maxPixelSize)
    }
}




// Required for `.sheet(item:)`, which presents based on a non-nil Identifiable item.
extension ChatAttachment: Identifiable {
    public var id: NSManagedObjectID { objectID }
}
