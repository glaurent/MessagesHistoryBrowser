//
//  AttachmentsCollectionViewDelegate.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 17/12/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

protocol AttachmentsCollectionViewDelegate: NSCollectionViewDelegate {

    func displayAttachmentAtIndexPath(indexPath:NSIndexPath) -> Void
    func showAttachmentInFinderAtIndexPath(indexPath:NSIndexPath) -> Void

}
