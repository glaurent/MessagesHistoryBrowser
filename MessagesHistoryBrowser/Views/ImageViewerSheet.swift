//
//  ImageViewerSheet.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 07/10/2026.
//  Copyright © 2026 Guillaume Laurent. All rights reserved.
//

import Foundation
import SwiftUI

struct ImageViewerSheet: View {
    let attachments: [ViewableChatAttachment]
    // Owned by the viewer and seeded from the attachment the sheet was
    // presented with, so it's valid from the very first render.
    @State private var selectedAttachment: ViewableChatAttachment?
    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: NSImage?
    @State private var isLoading = true

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter
    }()

    init(attachments: [ViewableChatAttachment], initialAttachment: ViewableChatAttachment) {
        self.attachments = attachments
        _selectedAttachment = State(initialValue: initialAttachment)
    }

    private var currentIndex: Int? {
        guard let selectedAttachment else { return nil }
        return attachments.firstIndex(where: { $0.attachmentID == selectedAttachment.attachmentID })
    }

    private var canGoPrevious: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }

    private var canGoNext: Bool {
        guard let index = currentIndex else { return false }
        return index < attachments.count - 1
    }

    var body: some View {
        Group {
            if let fullImage = fullImage {
                Image(nsImage: fullImage)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .transition(.opacity)
                    .id(selectedAttachment?.attachmentID)
            } else if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Preview unavailable")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("This attachment can't be displayed. It may be stored in iCloud or be a non-image file.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selectedAttachment?.attachmentID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        // Previous / next navigation
        .overlay(alignment: .leading) {
            navigationButton(systemName: "chevron.left", key: .leftArrow, enabled: canGoPrevious, action: goToPrevious)
                .padding(.leading, 16)
        }
        .overlay(alignment: .trailing) {
            navigationButton(systemName: "chevron.right", key: .rightArrow, enabled: canGoNext, action: goToNext)
                .padding(.trailing, 16)
        }
        // Caption bar with position and date
        .overlay(alignment: .bottom) {
            if let selectedAttachment {
                HStack(spacing: 6) {
                    Text(ImageViewerSheet.dateFormatter.string(from: selectedAttachment.date))
                    if let index = currentIndex {
                        Text("·")
                        Text("\(index + 1) of \(attachments.count)")
                    }
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 24)
            }
        }
        // Close button
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 520)
        .task(id: selectedAttachment?.attachmentID) {
            await loadFullImage()
        }
    }

    // Arrow keys are bound as keyboard shortcuts on the buttons rather than via
    // .onKeyPress, which only fires when the view has keyboard focus.
    @ViewBuilder
    private func navigationButton(systemName: String, key: KeyEquivalent, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .opacity(enabled ? 1 : 0.25)
        .disabled(!enabled)
    }

    private func goToPrevious() {
        guard let index = currentIndex, index > 0 else { return }
        selectedAttachment = attachments[index - 1]
    }

    private func goToNext() {
        guard let index = currentIndex, index < attachments.count - 1 else { return }
        selectedAttachment = attachments[index + 1]
    }

    private func loadFullImage() async {
        isLoading = true
        fullImage = await selectedAttachment?.fullImage()
        isLoading = false
    }
}


#Preview("Image Viewer") {
    ImageViewerSheetPreviewContainer()
}

private struct ChatAttachmentForPreview: ViewableChatAttachment {
    let attachmentID: AnyHashable = UUID()

    let date: Date = Date()

    func fullImage() async -> NSImage? {
        NSImage(imageLiteralResourceName: "placeholder")
    }
    

}

// Builds an in-memory Core Data graph and a few generated placeholder images
// so the viewer's navigation and layout can be exercised without a real
// Messages database or attachment files on disk.
private struct ImageViewerSheetPreviewContainer: View {
    private static let attachments: [ViewableChatAttachment] = [ChatAttachmentForPreview(), ChatAttachmentForPreview(), ChatAttachmentForPreview()]

    var body: some View {
        ImageViewerSheet(attachments: Self.attachments, initialAttachment: Self.attachments[1])
    }


}
