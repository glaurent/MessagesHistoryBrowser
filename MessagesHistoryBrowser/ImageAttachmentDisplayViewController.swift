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

    var image:NSImage? {
        set {
            // TODO - limit image size
            if let newImage = newValue {
                let newImageSize = newImage.size
                let mainScreenSize = NSScreen.mainScreen()!.frame.size

                if newImageSize.height > mainScreenSize.height || newImageSize.width > mainScreenSize.width {
                    view.frame.size = NSSize(width: mainScreenSize.width / 2.0, height: mainScreenSize.height / 2.0)
                } else {
                    view.frame.size = newImageSize
                }
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

        let mainScreenSize = NSScreen.mainScreen()!.frame.size

        view.window?.maxSize = NSSize(width: mainScreenSize.width * 0.75, height: mainScreenSize.height / 0.75)
    }



}
