//
//  AttachmentThumbnailCache.swift
//  MessagesHistoryBrowser
//
//  Bounded, cached, off-main-thread thumbnail decoding for attachment files.
//

import Cocoa
import ImageIO

// Thumbnails for the attachment grid and the inline images in the message
// list.
//
// Decoding an attachment with NSImage(contentsOfFile:) materializes the whole
// bitmap (a 12 MP photo is ~48 MB) just to draw a 120 pt cell, on a global
// queue with no concurrency limit, and again every time the cell scrolls back
// into view. This object instead:
//
//  - asks ImageIO for a thumbnail no larger than the requested pixel size, so
//    JPEG/HEIC files are decoded at reduced resolution and never fully
//    expanded;
//  - runs the decodes on an operation queue with a fixed concurrency limit,
//    so a fast scroll through a large grid does not spawn dozens of parallel
//    decodes;
//  - caches results (including "not an image") in a cost-bounded NSCache,
//    keyed by path and size, so a cell scrolled back into view is free;
//  - cancels queued (not yet started) decodes whose requesting view has gone.
final class AttachmentThumbnailCache {

    static let shared = AttachmentThumbnailCache()

    // Cached value. A class so NSCache can hold it, optional image so a
    // failed decode (video, vCard, iCloud placeholder...) is remembered too
    // and not retried on every appearance.
    private final class Entry {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }

    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = 96 * 1024 * 1024   // bytes of decoded thumbnails
        cache.countLimit = 4000
        return cache
    }()

    private let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "AttachmentThumbnailCache.decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        return queue
    }()

    // Returns a thumbnail of the image file at `path` whose longest side is
    // at most `maxPixelSize` pixels, or nil if the file is not a decodable
    // image. Safe to call from any context; the decode happens off the
    // caller's thread. Cancelling the calling task cancels the decode if it
    // has not started yet.
    func thumbnail(forFileAt path: String, maxPixelSize: Int) async -> NSImage? {
        let key = AttachmentThumbnailCache.cacheKey(path: path, maxPixelSize: maxPixelSize)

        if let entry = cache.object(forKey: key) {
            return entry.image
        }

        let operation = DecodeOperation { [cache] in
            // Another operation for the same file may have finished while this
            // one was queued.
            if let entry = cache.object(forKey: key) {
                return entry.image
            }
            let image = AttachmentThumbnailCache.decodeThumbnail(at: path, maxPixelSize: maxPixelSize)
            cache.setObject(Entry(image), forKey: key, cost: AttachmentThumbnailCache.cost(of: image))
            return image
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                // The completion block runs once the operation finishes, whether
                // it ran or was cancelled before starting, so the continuation
                // is always resumed exactly once.
                operation.completionBlock = { [unowned operation] in
                    continuation.resume(returning: operation.result)
                }
                decodeQueue.addOperation(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    // Decodes a thumbnail directly from the file with ImageIO. Unlike a full
    // NSImage load, the decoder is told the target size up front, so for
    // JPEG and HEIC it works at reduced resolution and the full-size bitmap
    // never exists in memory. EXIF orientation is applied.
    static func decodeThumbnail(at path: String, maxPixelSize: Int) -> NSImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url, sourceOptions),
              // Not an image (video, vCard, ...): bail out before ImageIO logs
              // a "failed to create thumbnail" error for it.
              CGImageSourceGetType(source) != nil else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,   // don't settle for a tiny embedded EXIF thumbnail
            kCGImageSourceCreateThumbnailWithTransform: true,     // honour EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,           // decode now, on this background thread
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else { return nil }

        // Wrap the bitmap as-is rather than through NSImage(cgImage:size:),
        // whose snapshot representation re-renders at the screen's scale and
        // reports doubled pixel dimensions on Retina. Size in points equals
        // pixels; SwiftUI scales the image to fit its frame anyway.
        let representation = NSBitmapImageRep(cgImage: cgImage)
        let image = NSImage(size: NSSize(width: cgImage.width, height: cgImage.height))
        image.addRepresentation(representation)
        return image
    }

    private static func cacheKey(path: String, maxPixelSize: Int) -> NSString {
        return "\(maxPixelSize)|\(path)" as NSString
    }

    // Approximate decoded size in bytes, for NSCache's cost accounting.
    private static func cost(of image: NSImage?) -> Int {
        guard let image = image, let representation = image.representations.first else { return 1 }
        return representation.pixelsWide * representation.pixelsHigh * 4
    }

    // An Operation that produces a value, so the async wrapper can read it
    // from the completion block.
    private final class DecodeOperation: Operation, @unchecked Sendable {
        private let work: () -> NSImage?
        private(set) var result: NSImage?

        init(work: @escaping () -> NSImage?) {
            self.work = work
        }

        override func main() {
            guard !isCancelled else { return }
            result = work()
        }
    }
}
