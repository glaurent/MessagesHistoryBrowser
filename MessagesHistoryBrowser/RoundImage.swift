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

    let newSize = NSSize(width:esize.width, height:esize.height)
    let composedImage = NSImage(size: newSize)

    composedImage.lockFocus()
    let ctx = NSGraphicsContext.current
    ctx?.imageInterpolation = NSImageInterpolation.high

    let imageFrame = NSRect(x: 0, y: 0, width: esize.width, height: esize.height)
    let clipPath = NSBezierPath(ovalIn: imageFrame)
    clipPath.windingRule = NSBezierPath.WindingRule.evenOddWindingRule
    clipPath.addClip()

    let rect = NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
    image.draw(at: NSZeroPoint, from: rect, operation: NSCompositingOperation.sourceOver, fraction: 1)
    composedImage.unlockFocus()

    return composedImage
}
