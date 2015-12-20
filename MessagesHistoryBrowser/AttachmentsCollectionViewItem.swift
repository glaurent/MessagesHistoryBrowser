//
//  AttachmentsCollectionViewItem.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 11/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class AttachmentsCollectionViewItem: NSCollectionViewItem {

    override var selected:Bool {
        didSet {
            if selected {
                view.layer?.borderColor = NSColor.selectedMenuItemColor().CGColor
                view.layer?.borderWidth = 4.0
            } else {
                view.layer?.borderColor = NSColor.clearColor().CGColor
                view.layer?.borderWidth = 0.0
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        view.layer?.cornerRadius = 5.0
    }

}
