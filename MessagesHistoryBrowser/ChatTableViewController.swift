//
//  ChatTableViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 25/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class ChatTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var searchField: NSSearchField!

    var chatsDatabase:ChatsDatabase!

    var messagesListViewController:MessagesListViewController?

    var allKnownContacts:[ChatContact]!
    var allUnknownContacts:[ChatContact]!

    lazy var moc = (NSApp.delegate as! AppDelegate).managedObjectContext

    var messageFormatter = MessageFormatter()

    var showChatsFromUnknown = false
    
    var searchMode = false
    var searchedContacts:[ChatContact]?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        chatsDatabase = ChatsDatabase.sharedInstance

        allKnownContacts = ChatContact.allKnownContactsInContext(moc)
        allUnknownContacts = ChatContact.allUnknownContactsInContext(moc)

        if let parentSplitViewController = parentViewController as? NSSplitViewController {
            let secondSplitViewItem = parentSplitViewController.splitViewItems[1]

            messagesListViewController = secondSplitViewItem.viewController as? MessagesListViewController
        }

        NSNotificationCenter.defaultCenter().addObserver(self, selector: "showUnknownContactsChanged:", name: AppDelegate.ShowChatsFromUnknownNotification, object: nil)

    }

    func showUnknownContactsChanged(notification:NSNotification)
    {
        let appDelegate = NSApp.delegate as! AppDelegate
        showChatsFromUnknown = appDelegate.showChatsFromUnknown
        tableView.reloadData()
    }

    func contactForRow(row:Int) -> ChatContact {
        var contact:ChatContact

        if searchMode {
            
            contact = searchedContacts![row]
            
        } else {
            if showChatsFromUnknown && row >= allKnownContacts.count {
                contact = allUnknownContacts[row - allKnownContacts.count]
            } else {
                contact = allKnownContacts[row]
            }
        }
        return contact
    }

    // MARK: NSTableView datasource & delegate

    func numberOfRowsInTableView(tableView: NSTableView) -> Int
    {
        if searchMode {
            return searchedContacts?.count ?? 0
        }
        
        if showChatsFromUnknown {
            return allKnownContacts.count + allUnknownContacts.count
        }

        return allKnownContacts.count
    }


    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView?
    {
        guard let tableColumn = tableColumn else { return nil }

        let cellView = tableView.makeViewWithIdentifier(tableColumn.identifier, owner: self) as! NSTableCellView

        let contact = contactForRow(row)

        cellView.textField?.stringValue = contact.name

        return cellView
    }

    func tableViewSelectionDidChange(notification: NSNotification)
    {
        let index = tableView.selectedRowIndexes.firstIndex // no multiple selection

        let selectedContact = contactForRow(index)

        chatsDatabase.collectMessagesForContact(selectedContact)

        let allContactMessagesT = selectedContact.messages.allObjects.sort { (a, b) -> Bool in
            let aMessage = a as! ChatMessage
            let bMessage = b as! ChatMessage

            return aMessage.date.isLessThan(bMessage.date)
        }

        let allContactAttachmentsT = selectedContact.attachments.allObjects.sort { (a, b) -> Bool in
            let aAttachment = a as! ChatAttachment
            let bAttachment = b as! ChatAttachment

            return aAttachment.date.isLessThan(bAttachment.date)
        }

        let allContactMessages = allContactMessagesT as! [ChatMessage]

        var allMessages = ""

        for message in allContactMessages {
            allMessages = allMessages + messageFormatter.formatMessage(message) + "\n"
        }

        messagesListViewController?.attachmentsToDisplay = allContactAttachmentsT as? [ChatAttachment]
        messagesListViewController?.attachmentsCollectionView.reloadData()
        messagesListViewController?.messagesTextView.string = allMessages
    }


    func tableViewSelectionDidChange_old(notification: NSNotification)
    {

        let selectedRowIndexes = tableView.selectedRowIndexes

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

            for message in messagesForChatGUID {
                allMessages = allMessages + messageFormatter.formatMessage(message) + "\n"
            }
        }
        
        messagesListViewController?.attachmentsToDisplay = allAttachmentsToDisplay
        messagesListViewController?.attachmentsCollectionView.reloadData()
        messagesListViewController?.messagesTextView.string = allAttachmentsFileNames + "\n\n" + allMessages
    }

    func chatIDsForSelectedRows(selectedRowIndexes : NSIndexSet) -> [Chat]
    {
        let index = selectedRowIndexes.firstIndex // no multiple selection

        let selectedContact = contactForRow(index)

        return selectedContact.chats.allObjects as! [Chat]

    }

    @IBAction func search(sender: NSSearchField) {

        NSLog("search for '\(sender.stringValue)'")

        if sender.stringValue == "" {
            
            searchMode = false
            searchedContacts = nil
            
        } else {
            
            let matchingMessages = ChatsDatabase.sharedInstance.searchChatsForString(sender.stringValue)
            
            var allMatchingMessages = ""
            
            for message in matchingMessages {
                let chatMessage = message.chat
                allMatchingMessages = allMatchingMessages + "\(chatMessage.guid) : " + (message.content ?? "") + "\n"
            }
            
            messagesListViewController?.messagesTextView.string = allMatchingMessages
            
            searchedContacts = contactsFromMessages(matchingMessages)
            searchMode = true
            
        }
        
        tableView.reloadData()
    }


    func contactsFromMessages(messages: [ChatMessage]) -> [ChatContact]
    {
        let allContacts = messages.map { (message) -> ChatContact in
            return message.contact
        }
        
        var contactList = [String:ChatContact]()
        
        let uniqueContacts = allContacts.filter { (contact) -> Bool in
            if contactList[contact.name] != nil {
                return false
            }
            contactList[contact.name] = contact
            return true
        }
        
        return uniqueContacts
    }
}
