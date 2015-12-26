//
//  ChatListViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 20/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

// NOT USED due to apparent bug in NSOutlineView which causes it to crash after a reloadData()

import Cocoa

class ChatListViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {

    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var searchField: NSSearchField!

    var chatsDatabase:ChatsDatabase!

    var messagesListViewController:MessagesListViewController?

    var allKnownContacts:[ChatContact]!
    var allUnknownContacts:[ChatContact]!

    lazy var moc = MOCController.sharedInstance.managedObjectContext

    var messageFormatter = MessageFormatter()

    override func viewDidLoad()
    {
        super.viewDidLoad()
        // Do view setup here.

        chatsDatabase = ChatsDatabase.sharedInstance

        allKnownContacts = ChatContact.allKnownContactsInContext(moc)
        allUnknownContacts = ChatContact.allUnknownContactsInContext(moc)

        outlineView.reloadData()

        if let parentSplitViewController = parentViewController as? NSSplitViewController {
            let secondSplitViewItem = parentSplitViewController.splitViewItems[1]

            messagesListViewController = secondSplitViewItem.viewController as? MessagesListViewController
        }

    }


// MARK: NSOutlineViewDataSource
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject
    {
//        print("child index \(index) of item \(item)")

        if item == nil {
            switch index {
            case 0:
                return NSString(string:knownCategoryLabel)

            case 1:
                return NSString(string:unKnownCategoryLabel)

            default:
                NSLog("\(__FUNCTION__) : unknown index \(index)")
                return NSString(string:"ERROR INDEX \(index)")
            }
        }

        if let knownOrUnknown = item as? String {

            if knownOrUnknown == knownCategoryLabel {
                let contact = allKnownContacts[index]
//            print("contact : \(contact.name)")
//            print("res : \(res)")
//            return NSString(string: res.name) // REALLY have to return an NSString here, or we get memory corruptions. NSOutlineView doesn't like Swift Strings.
                return contact
            } else {
                return allUnknownContacts[index]
            }
        }

        if let contact = item as? ChatContact {
            let chatsForContactName = contact.chats
            let chat = chatsForContactName.allObjects[index]
//                print("return chat \(chat.guid)")
            return chat
        }

        if item is Chat {
            return "ERROR - CHAT"
        }

        return "ERROR"
    }

//    func outlineView(outlineView: NSOutlineView, objectValueForTableColumn tableColumn: NSTableColumn?, byItem item: AnyObject?) -> AnyObject?
//    {
//
//        if item == nil {
//            return "chats"
//        }
//
//        if item is String {
//
//            if let tableColumn = tableColumn {
//                if tableColumn.identifier == "Chats" {
//                    return item // should be the contact name
//                } else {
//                    return ""
//                }
//            }
//
//        } else if item is Chat {
//            let chat = item as! Chat
//
//            if let tableColumn = tableColumn {
//                if tableColumn.identifier == "Chats" {
//                    return chat.guid
//                } else {
//                    return nil // TODO: return some useful metadata (date ?)
//                }
//            }
//
//        }
//
//        return nil
//    }

    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool
    {
//        print("item \(item) isExpandable")

        if let _ = item as? String { // "known" / "unknown" top categories
            return true
        }

        if let contactName = item as? ChatContact {
            let chatsForContactName = contactName.chats
            return chatsForContactName.count > 0 // should be always true in this case anyway
        }

        return false
    }

    let knownCategoryLabel = "known"
    let unKnownCategoryLabel = "unknown"

    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int
    {
//        print("number of children of item \(item)")

        if item == nil {
            return 2 // "known" or "unknown"
        }

        if let knownOrUnknown = item as? String {
            if knownOrUnknown == knownCategoryLabel {
                return allKnownContacts.count
            } else {
                return allUnknownContacts.count
            }
        }

        if let contact = item as? ChatContact {
            return contact.chats.count
        }

        return 1
    }

    let fakeContactName = "ContactName"
    let fakeChatId = "a chat"

    // MARK: NSOutlineViewDelegate
    func outlineView(outlineView: NSOutlineView, viewForTableColumn: NSTableColumn?, item: AnyObject) -> NSView?
    {

        let view = outlineView.makeViewWithIdentifier("Chats", owner: self) as! NSTableCellView
        if let textField = view.textField {
            if let itemString = item as? String {
                textField.stringValue = itemString
            } else if let itemContact = item as? ChatContact {
                textField.stringValue = itemContact.name
            } else if let itemChat = item as? Chat {
                textField.stringValue = "chat GUID : \(itemChat.guid)"
            }
        }
        return view
    }

    func outlineViewSelectionDidChange(notification: NSNotification)
    {
        let selectedRowIndexes = outlineView.selectedRowIndexes

        let chatIDs = chatIDsForSelectedRows(selectedRowIndexes)

        // messages and attachments indexed by chat GUIDs
        var messages = [String:[ChatMessage]]()
        var attachments = [String:[ChatAttachment]]()

        // all attachments for all selected chats
        var allAttachmentsToDisplay = [ChatAttachment]()

        for chatID in chatIDs {
            let (messagesForChat, attachmentsForChat) = chatsDatabase.messagesForChat(chatID)
            messages[chatID.guid] = messagesForChat
            attachments[chatID.guid] = attachmentsForChat
        }

        var allAttachmentsFileNames = ""
        for (chatGUID, attachmentsForChatGUID) in attachments {
            allAttachmentsFileNames = allAttachmentsFileNames + "\n\t\(chatGUID)\n"
            for attachment in attachmentsForChatGUID {
//                let attachmentFileName = attachment.fileName ?? "<no filename>"
//                allAttachmentsFileNames = allAttachmentsFileNames + "\(attachment.date) : \(attachmentFileName)\n"
                allAttachmentsToDisplay.append(attachment)
            }
        }

        var allMessages = ""

        for (chatGUID, messagesForChatGUID) in messages {

            allMessages = allMessages + "\n\t\(chatGUID)\n"

//            for message in messagesForChatGUID {
//                allMessages = allMessages + messageFormatter.formatMessage(message) + "\n"
//            }
        }

        messagesListViewController?.attachmentsToDisplay = allAttachmentsToDisplay
        messagesListViewController?.attachmentsCollectionView.reloadData()
//        messagesListViewController?.messagesTextView.string = allAttachmentsFileNames + "\n\n" + allMessages
    }

    func chatIDsForSelectedRows(selectedRowIndexes : NSIndexSet) -> [Chat]
    {
        var chatIDs = [Chat]()

        selectedRowIndexes.enumerateIndexesUsingBlock { (index:Int, stop:UnsafeMutablePointer<ObjCBool>) -> Void in
            let cellValue = self.outlineView.itemAtRow(index)

//            NSLog("cellValue at index \(index) : \(cellValue)")
            if cellValue is Chat {
                chatIDs.append(cellValue as! Chat)
            } else if cellValue is ChatContact {
                let nbChildren = self.outlineView(self.outlineView, numberOfChildrenOfItem:cellValue)
                for childIndex in 0..<nbChildren {
                    if let chat = self.outlineView(self.outlineView, child:childIndex, ofItem:cellValue) as? Chat {
                        chatIDs.append(chat)
                    }
                }
            }
        }

        return chatIDs
    }

    @IBAction func search(sender: NSSearchField) {

        NSLog("search for '\(sender.stringValue)'")

        let matchingMessages = ChatsDatabase.sharedInstance.searchChatsForString(sender.stringValue)

        var allMatchingMessages = ""

        for message in matchingMessages {
            let chatMessage = message.chat
            allMatchingMessages = allMatchingMessages + "\(chatMessage.guid) : " + (message.content ?? "") + "\n"
        }

        messagesListViewController?.messagesTextView.string = allMatchingMessages
    }
    
    
    @IBAction func refreshChatHistory(sender: AnyObject) {
        
//        let appDelegate = NSApp.delegate as! AppDelegate
//
//        appDelegate.clearAllCoreData()

        outlineView.reloadData()
        
//        ChatsDatabase.sharedInstance.importAllChatsFromDB()
//
//        allKnownContacts = ChatContact.allKnownContactsInContext(moc)
//        allUnknownContacts = ChatContact.allUnknownContactsInContext(moc)

//        ChatsDatabase.sharedInstance.collectAllMessagesFromAllChats()

//        outlineView.reloadData()
    }
}
