//
//  MessagesListViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 04/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class MessagesListViewController: NSViewController, NSCollectionViewDataSource, AttachmentsCollectionViewDelegate {

    let collectionViewItemID = "AttachmentsCollectionViewItem"

    let windowControllerId = "ImageAttachmentDisplayWindowController"

    @IBOutlet weak var attachmentsCollectionView: NSCollectionView!
    @IBOutlet var messagesTextView: NSTextView!

    var attachmentsToDisplay:[ChatAttachment]?

    let dateFormatter = NSDateFormatter()

    let messageFormatter = MessageFormatter()

    let delayBetweenChatsInSeconds = NSTimeInterval(24 * 3600)
    
    var terseTimeMode = true {
        didSet {
            messageFormatter.terseTimeMode = terseTimeMode
        }
    }

    var currentImageAttachmentDisplayWindowController:NSWindowController?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do view setup here.

        dateFormatter.timeStyle = .ShortStyle
        dateFormatter.dateStyle = .ShortStyle

        let aNib = NSNib(nibNamed: collectionViewItemID, bundle: nil)

        attachmentsCollectionView.registerNib(aNib, forItemWithIdentifier: collectionViewItemID)

//        let gridLayout = NSCollectionViewGridLayout()
//        gridLayout.minimumItemSize = NSSize(width: 100, height: 100)
//        gridLayout.maximumItemSize = NSSize(width: 175, height: 175)
//        gridLayout.minimumInteritemSpacing = 10
//        gridLayout.margins = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
//        attachmentsCollectionView.collectionViewLayout = gridLayout

        if let flowLayout = attachmentsCollectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
            flowLayout.minimumInteritemSpacing = 15.0
        }

//        terseTimeMode = false

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

        let item = collectionView.makeItemWithIdentifier(collectionViewItemID, forIndexPath: indexPath)

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


    func collectionView(collectionView: NSCollectionView, didSelectItemsAtIndexPaths indexPaths: Set<NSIndexPath>)
    {
        NSLog("didSelectItemsAtIndexPaths \(indexPaths)")

        if let attachment = attachmentsToDisplay?[indexPaths.first!.item] {
            if let range = attachment.associatedRange {
                messagesTextView.scrollRangeToVisible(range)
            }
        }

    }

    // MARK: attachments display

    func displayAttachmentAtIndexPath(indexPath: NSIndexPath) {
        NSLog("displayAttachmentAtIndexPath \(indexPath)")

        if currentImageAttachmentDisplayWindowController == nil {
            currentImageAttachmentDisplayWindowController = self.storyboard!.instantiateControllerWithIdentifier(self.windowControllerId) as? NSWindowController
        }

        let imageAttachmentDisplayViewController = currentImageAttachmentDisplayWindowController?.contentViewController as! ImageAttachmentDisplayViewController

        if let image = imageForAttachmentAtIndexPath(indexPath) {

            imageAttachmentDisplayViewController.image = image

//            currentImageAttachmentDisplayWindowController.window?.level = Int(CGWindowLevelKey.FloatingWindowLevelKey.rawValue)
            currentImageAttachmentDisplayWindowController?.showWindow(self)
            view.window?.makeKeyWindow()

        }

    }

    func hideAttachmentDisplayWindow()
    {
        currentImageAttachmentDisplayWindowController?.window?.orderOut(self)
    }

    func imageForAttachmentAtIndexPath(indexPath:NSIndexPath) -> NSImage?
    {
        if let attachment = attachmentsToDisplay?[indexPath.item], attachmentFileName = attachment.fileName {

            let imagePath = NSString(string:attachmentFileName).stringByStandardizingPath
            let image = NSImage(byReferencingFile: imagePath)
            return image
        }

        return nil
    }

    func clearMessages()
    {
        messagesTextView.string = ""
    }
    
    func showMessages(chatItems:[ChatItem], withHighlightTerm highlightTerm:String? = nil)
    {
        let allMatchingMessages = NSMutableAttributedString()

        var lastShownDate:NSDate?
        
        for chatItem in chatItems {

            if terseTimeMode {
                if lastShownDate == nil || chatItem.date.timeIntervalSinceDate(lastShownDate!) > delayBetweenChatsInSeconds {
                    let highlightedDate = messageFormatter.formatMessageDate(chatItem.date)
                    allMatchingMessages.appendAttributedString(highlightedDate)
                }
                
                lastShownDate = chatItem.date
            }
            
            if let message = chatItem as? ChatMessage {
                guard let highlightedMessage = messageFormatter.formatMessage(message, withHighlightTerm: highlightTerm) else { continue }

                allMatchingMessages.appendAttributedString(highlightedMessage)
            } else {
                let attachment = chatItem as! ChatAttachment

                guard let attachmentFileName = attachment.fileName else { continue }

                let attachmentPath = NSString(string:attachmentFileName).stringByStandardizingPath

                let attachmentURL = NSURL(fileURLWithPath: attachmentPath, isDirectory: false)

                do {
                    let textAttachment:NSTextAttachment

                    if isAttachmentImage(attachment) {

                        textAttachment = NSTextAttachment()
                        let image = NSImage(byReferencingFile: attachmentPath)
                        let textAttachmentCell = ImageAttachmentCell(imageCell: image)
                        textAttachment.attachmentCell = textAttachmentCell

                        let associatedRange = NSRange(location: allMatchingMessages.length, length: 1)
                        attachment.associatedRange = associatedRange

                    } else {

                        let attachmentFileWrapper = try NSFileWrapper(URL: attachmentURL, options:NSFileWrapperReadingOptions(rawValue: 0))
                        textAttachment = NSTextAttachment(fileWrapper: attachmentFileWrapper)

                    }

                    let attachmentString = NSAttributedString(attachment: textAttachment)

                    let attachmentStringWithNewLine = NSMutableAttributedString(attributedString: attachmentString)

                    attachmentStringWithNewLine.appendAttributedString(NSAttributedString(string: "\n"))

                    allMatchingMessages.appendAttributedString(attachmentStringWithNewLine)

                } catch {
                    NSLog("Couldn't create filewrapper for \(attachment.fileName)")
                }
            }
        }

        clearMessages()
        messagesTextView.textStorage?.insertAttributedString(allMatchingMessages, atIndex: 0)

    }

    func isAttachmentImage(attachment:ChatAttachment) -> Bool
    {
        guard let attachmentFileName = attachment.fileName else { return false }

        let pathString = NSString(string:attachmentFileName)

        let pathExtension = pathString.pathExtension

        if let utType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension, nil)?.takeRetainedValue() {

            return UTTypeConformsTo(utType, kUTTypeImage)
        }

        return false
    }

}
