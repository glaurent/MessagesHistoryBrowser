//
//  ChatListViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 20/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import AddressBook

class ChatListViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {

    @IBOutlet weak var outlineView: NSOutlineView!

    var chatsDatabase:ChatsDatabase!

    var messagesListViewController:MessagesListViewController?

    var allContacts:[ChatContact]!

    lazy var moc = (NSApp.delegate as! AppDelegate).managedObjectContext

    override func viewDidLoad()
    {
        super.viewDidLoad()
        // Do view setup here.

        chatsDatabase = ChatsDatabase.sharedInstance

        outlineView.reloadData()

        if let parentSplitViewController = parentViewController as? NSSplitViewController {
            let secondSplitViewItem = parentSplitViewController.splitViewItems[1]

            messagesListViewController = secondSplitViewItem.viewController as? MessagesListViewController
        }

        allContacts = ChatContact.allContactsInContext(moc) 
    }


// MARK: NSOutlineViewDataSource
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject
    {
//        print("child index \(index) of item \(item)")

        if item == nil {
            let contact = allContacts[index]
//            print("contact : \(contact.name)")
//            print("res : \(res)")
//            return NSString(string: res.name) // REALLY have to return an NSString here, or we get memory corruptions. NSOutlineView doesn't like Swift Strings.
            return contact
        }

        if let contact = item as? ChatContact {
            let chatsForContactName = contact.chats
            let chat = chatsForContactName.array[index]
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

        if let contactName = item as? ChatContact {
            let chatsForContactName = contactName.chats
            return chatsForContactName.count > 0 // should be always true in this case anyway
        }

        return false
    }

    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int
    {
//        print("number of children of item \(item)")

        if item == nil {
//            return 5
            return ChatContact.allContactsInContext(moc).count
        }

        if let contact = item as? ChatContact {
            return contact.chats.count
        }

        return 1
    }

    // MARK: NSOutlineViewDelegate
    func outlineView(outlineView: NSOutlineView, viewForTableColumn: NSTableColumn?, item: AnyObject) -> NSView?
    {

        let view = outlineView.makeViewWithIdentifier("Chats", owner: self) as! NSTableCellView
        if let textField = view.textField {
            if let itemContact = item as? ChatContact {
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

        var messages = [String:[ChatMessage]]()
        var attachments = [String:[ChatAttachment]]()

        for chatID in chatIDs {
            let (messagesForChat, attachmentsForChat) = chatsDatabase.messagesForChat(chatID)
            messages[chatID.guid] = messagesForChat
            attachments[chatID.guid] = attachmentsForChat
        }

        var allAttachmentsFileNames = ""
        for (chatGUID, attachmentsForChatGUID) in attachments {
            allAttachmentsFileNames = allAttachmentsFileNames + "\n\t\(chatGUID)\n"
            for attachment in attachmentsForChatGUID {
                let attachmentFileName = attachment.fileName ?? "<no filename>"
                allAttachmentsFileNames = allAttachmentsFileNames + "\(attachment.date) : \(attachmentFileName)\n"
            }
        }

        var allMessages = ""

        for (chatGUID, messagesForChatGUID) in messages {

            allMessages = allMessages + "\n\t\(chatGUID)\n"

            for message in messagesForChatGUID {
                let messageContent = message.content ?? "<no message>"
                allMessages = allMessages + "\(message.date) : \(messageContent)\n"
            }
        }

        messagesListViewController?.messagesTextView.string = allAttachmentsFileNames + "\n\n" + allMessages
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

}
