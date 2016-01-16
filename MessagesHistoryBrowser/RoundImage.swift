//
//  RoundImage.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 16/01/16.
//  Copyright © 2016 Guillaume Laurent. All rights reserved.
//

import Cocoa


// Copied from http://stackoverflow.com/a/27157566/1081361

func roundCorners(image: NSImage) -> NSImage
{
    let existing = image
    let esize = existing.size

    let newSize = NSSize(width:esize.width, height:esize.height)
    let composedImage = NSImage(size: newSize)

    composedImage.lockFocus()
    let ctx = NSGraphicsContext.currentContext()
    ctx?.imageInterpolation = NSImageInterpolation.High

    let imageFrame = NSRect(x: 0, y: 0, width: esize.width, height: esize.height)
    let clipPath = NSBezierPath(ovalInRect: imageFrame)
    clipPath.windingRule = NSWindingRule.EvenOddWindingRule
    clipPath.addClip()

    let rect = NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
    image.drawAtPoint(NSZeroPoint, fromRect: rect, operation: NSCompositingOperation.CompositeSourceOver, fraction: 1)
    composedImage.unlockFocus()

    return composedImage
}
