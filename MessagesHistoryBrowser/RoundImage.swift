//
//  RoundImage.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 16/01/16.
//  Copyright © 2016 Guillaume Laurent. All rights reserved.
//

import Cocoa


// Copied from http://stackoverflow.com/a/27157566/1081361

func roundCorners(_ image: NSImage) -> NSImage
{
    let existing = image
    let esize = existing.size

    let sideLength = min(esize.width, esize.height) // make sure the resulting image is an actual circle - doesn't always look good if original image isn't properly centered

    let newSize = NSSize(width:sideLength, height:sideLength)
    let composedImage = NSImage(size: newSize)

    composedImage.lockFocus()
    let ctx = NSGraphicsContext.current
    ctx?.imageInterpolation = NSImageInterpolation.high

    let imageFrame = NSRect(x: 0, y: 0, width: sideLength, height: sideLength)
    let clipPath = NSBezierPath(ovalIn: imageFrame)
    clipPath.windingRule = NSBezierPath.WindingRule.evenOdd
    clipPath.addClip()

    let rect = NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
    image.draw(at: NSZeroPoint, from: rect, operation: NSCompositingOperation.sourceOver, fraction: 1)
    composedImage.unlockFocus()

    return composedImage
}
