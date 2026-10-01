//
//  RoundImage.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 16/01/16.
//  Copyright © 2016 Guillaume Laurent. All rights reserved.
//

import Cocoa

// Crops `image` to a centered square, downscales it to `maxPixelSize` pixels
// per side, and clips it to a circle. Returns nil if `image` can't be read as
// a bitmap.
//
// Contact photos can be full-resolution (several MB decoded); this app only
// ever shows them at 32 points. Caching the original size, as the previous
// lockFocus-based version did, meant each cached avatar cost as much memory
// as the source photo. Rendering through a CGContext at the final pixel size
// also replaces the deprecated NSView lockFocus()/unlockFocus() drawing.
func roundCorners(_ image: NSImage, maxPixelSize: Int) -> NSImage?
{
    guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

    // Crop to a centered square so the circle isn't stretched from a
    // non-square source photo.
    let sourceSide = min(sourceImage.width, sourceImage.height)
    let cropRect = CGRect(
        x: (sourceImage.width - sourceSide) / 2,
        y: (sourceImage.height - sourceSide) / 2,
        width: sourceSide,
        height: sourceSide
    )
    guard let croppedImage = sourceImage.cropping(to: cropRect) else { return nil }

    let side = max(1, min(maxPixelSize, sourceSide))
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    context.addEllipse(in: rect)
    context.clip()
    context.draw(croppedImage, in: rect)

    guard let outputImage = context.makeImage() else { return nil }

    // Wrap the bitmap directly rather than through NSImage(cgImage:size:),
    // whose snapshot representation re-renders at the screen's scale and so
    // reports doubled pixel dimensions on Retina (see AttachmentThumbnailCache,
    // which hit the same issue). Size in points equals pixels here; SwiftUI
    // scales the image to fit its frame regardless.
    let representation = NSBitmapImageRep(cgImage: outputImage)
    let result = NSImage(size: NSSize(width: side, height: side))
    result.addRepresentation(representation)
    return result
}
