//
//  ImageAttachmentCell.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 11/11/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

// taken from http://ossh.com.au/design-and-technology/software-development/implementing-rich-text-with-images-on-os-x-and-ios/
//

class ImageAttachmentCell: NSTextAttachmentCell {

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect
    {
        let width = lineFrag.size.width

        let imageRect = scaleImageToWidth(width)

        return imageRect
    }

    func scaleImageToWidth(_ width:CGFloat) -> NSRect
    {
        guard let image = self.image else { return NSZeroRect }

        var scalingFactor:CGFloat = 1.0

        let imageSize = image.size

        if (width < imageSize.width) {
            scalingFactor = (width * 0.9) / imageSize.width
        }

        let rect = NSRect(x:0, y:0, width:imageSize.width * scalingFactor, height:imageSize.height * scalingFactor)
        
        return rect;

    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?)
    {
        image?.draw(in: cellFrame, from: NSZeroRect, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
    }

}
