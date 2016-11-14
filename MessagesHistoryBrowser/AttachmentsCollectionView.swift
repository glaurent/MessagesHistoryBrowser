//
//  AttachmentsCollectionView.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 17/12/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class AttachmentsCollectionView: NSCollectionView {

    override func keyDown(with theEvent: NSEvent) {
        if theEvent.characters == " " {
            if selectionIndexPaths.count == 1 {
                if let attachmentsViewDelegate = delegate as? AttachmentsCollectionViewDelegate {
                    attachmentsViewDelegate.displayAttachmentAtIndexPath(selectionIndexPaths.first!)
                }
            }
        } else {
            super.keyDown(with: theEvent)
        }
    }

}
