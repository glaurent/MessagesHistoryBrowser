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

    }

    // MARK: NSTableView datasource & delegate

    func numberOfRowsInTableView(tableView: NSTableView) -> Int
    {
        return allKnownContacts.count
    }


    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView?
    {
        guard let tableColumn = tableColumn else { return nil }

        let cellView = tableView.makeViewWithIdentifier(tableColumn.identifier, owner: self) as! NSTableCellView

        cellView.textField?.stringValue = allKnownContacts[row].name

        return cellView
    }

    func tableViewSelectionDidChange(notification: NSNotification)
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

    let selectedContact = allKnownContacts[index]

    return selectedContact.chats.array as! [Chat]

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


}
