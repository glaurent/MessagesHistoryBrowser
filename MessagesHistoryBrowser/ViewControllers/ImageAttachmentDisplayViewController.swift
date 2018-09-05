//
//  ImageAttachmentDisplayViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 20/12/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class ImageAttachmentDisplayViewController: NSViewController {

    @IBOutlet weak var imageView: NSImageView!

    var halfScreenSize:NSSize!

    let windowTopBarHeight:CGFloat = 22.0

    let maxSizeScreenRatio:CGFloat = 4.0 // images won't be displayed larger than (screen size) * ratio

    var image:NSImage? {
        set {

            if let newImage = newValue {
                let newImageSize = newImage.size
                let mainScreenSize = NSScreen.main!.frame.size

                var newSize:NSSize

                if newImageSize.height > (mainScreenSize.height / maxSizeScreenRatio) || newImageSize.width > (mainScreenSize.width / maxSizeScreenRatio) {

                    newSize = size(newImageSize, inBounds:halfScreenSize)
//                    NSLog("initial size : \(newImage.size) - scaled down newSize : \(newSize)")

//                    newSize = NSSize(width: mainScreenSize.width / 2.0, height: mainScreenSize.height / 2.0)
                } else {
                    newSize = NSSize(width: newImageSize.width, height: newImageSize.height + windowTopBarHeight) // window top bar
                }

                var windowFrame = view.window!.frame
                windowFrame.size = newSize
//                NSLog("initial size : \(newImage.size) - scaled down newSize : \(newSize)")

                view.window?.setFrame(windowFrame, display: true, animate: true)

                view.needsLayout = true
                
                imageView.image = newImage
            }
        }

        get {
            return imageView.image
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        let mainScreenSize = NSScreen.main!.frame.size

        halfScreenSize = NSSize(width: mainScreenSize.width / maxSizeScreenRatio, height: mainScreenSize.height / maxSizeScreenRatio)

        view.window?.maxSize = NSSize(width: mainScreenSize.width / maxSizeScreenRatio, height: mainScreenSize.height / maxSizeScreenRatio)
    }

    func size(_ aSize:NSSize, inBounds bounds:NSSize) -> NSSize
    {
        let ratio = aSize.width / aSize.height

        let newWidthCandidate = bounds.height * ratio
        let newHeightCandidate = bounds.width / ratio

        let newHeight = newWidthCandidate / ratio

        if newHeight < bounds.height {
            return NSSize(width: newWidthCandidate, height: newHeight + windowTopBarHeight)
        } else {
            return NSSize(width: newHeightCandidate * ratio, height: newHeightCandidate + windowTopBarHeight)
        }
    }

}
