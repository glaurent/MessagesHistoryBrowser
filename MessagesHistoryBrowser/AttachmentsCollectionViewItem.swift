//
//  AttachmentsCollectionViewItem.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 11/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class AttachmentsCollectionViewItem: NSCollectionViewItem {

    override var isSelected:Bool {
        didSet {
            if isSelected {
                view.layer?.borderColor = NSColor.selectedMenuItemColor.cgColor
                view.layer?.borderWidth = 4.0
            } else {
                view.layer?.borderColor = NSColor.clear.cgColor
                view.layer?.borderWidth = 0.0
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        view.layer?.cornerRadius = 5.0
    }

    @IBAction func showInFinder(_ sender:AnyObject)
    {
        if let delegate = collectionView?.delegate as? AttachmentsCollectionViewDelegate {
            NSLog("showInFinder")
            if let thisItemIndexPath = collectionView?.indexPath(for: self) {
                delegate.showAttachmentInFinderAtIndexPath(thisItemIndexPath)
            }
        }
    }

}
