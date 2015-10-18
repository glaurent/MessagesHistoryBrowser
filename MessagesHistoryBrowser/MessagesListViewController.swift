//
//  MessagesListViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 04/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class MessagesListViewController: NSViewController, NSCollectionViewDataSource {

    static let collectionViewItemID = "AttachmentsCollectionViewItem"

    @IBOutlet weak var attachmentsCollectionView: NSCollectionView!
    @IBOutlet var messagesTextView: NSTextView!

    var attachmentsToDisplay:[ChatAttachment]?

    let dateFormatter = NSDateFormatter()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do view setup here.

        dateFormatter.timeStyle = .ShortStyle
        dateFormatter.dateStyle = .ShortStyle

        attachmentsCollectionView.dataSource = self // Xcode 7.0.1 crashes when trying to open the connections tab of the collection view

        let aNib = NSNib(nibNamed: MessagesListViewController.collectionViewItemID, bundle: nil)

        attachmentsCollectionView.registerNib(aNib, forItemWithIdentifier: MessagesListViewController.collectionViewItemID)

        let gridLayout = NSCollectionViewGridLayout()
        gridLayout.minimumItemSize = NSSize(width: 100, height: 100)
        gridLayout.maximumItemSize = NSSize(width: 175, height: 175)
        gridLayout.minimumInteritemSpacing = 10
        gridLayout.margins = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        attachmentsCollectionView.collectionViewLayout = gridLayout

    }


    func collectionView(collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int
    {
        guard let attachmentsToDisplay = attachmentsToDisplay else {
            return 0
        }

        return attachmentsToDisplay.count
    }

    func collectionView(collectionView: NSCollectionView, itemForRepresentedObjectAtIndexPath indexPath: NSIndexPath) -> NSCollectionViewItem
    {
        let attachmentsToDisplay = self.attachmentsToDisplay!

        let attachment = attachmentsToDisplay[indexPath.item]

        let item = collectionView.makeItemWithIdentifier(MessagesListViewController.collectionViewItemID, forIndexPath: indexPath)

        if let attachmentFileName = attachment.fileName {

            let imagePath = NSString(string:attachmentFileName).stringByStandardizingPath
            let image = NSImage(byReferencingFile: imagePath)
            item.imageView?.image = image
            item.textField?.stringValue = dateFormatter.stringFromDate(attachment.date)
        } else {
            item.textField?.stringValue = "unknown"
        }

        return item
    }

}
