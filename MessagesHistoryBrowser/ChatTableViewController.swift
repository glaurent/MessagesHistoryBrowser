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
    @IBOutlet weak var afterDatePicker: NSDatePicker!
    @IBOutlet weak var beforeDatePicker: NSDatePicker!

    var chatsDatabase:ChatsDatabase!

    var messagesListViewController:MessagesListViewController?

    var allKnownContacts:[ChatContact]!
    var allUnknownContacts:[ChatContact]!

    lazy var moc = (NSApp.delegate as! AppDelegate).managedObjectContext

    var messageFormatter = MessageFormatter()

    var showChatsFromUnknown = false
    
    var searchMode = false
    var searchedContacts:[ChatContact]?

    dynamic var beforeDateEnabled = false
    dynamic var afterDateEnabled = false
    
    dynamic var beforeDate = NSDate()
    dynamic var afterDate = NSDate()
    
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

    func contactForRow(row:Int) -> ChatContact? {
        
        guard (searchMode && row < searchedContacts!.count) || (showChatsFromUnknown && row < allKnownContacts.count + allUnknownContacts.count) || row < allKnownContacts.count else { return nil }
        
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

        if let contact = contactForRow(row) {
            cellView.textField?.stringValue = contact.name
        }
        
        return cellView
    }

    func tableViewSelectionDidChange(notification: NSNotification)
    {
        let index = tableView.selectedRowIndexes.firstIndex // no multiple selection

        guard let selectedContact = contactForRow(index) else { return }
        
        chatsDatabase.collectMessagesForContact(selectedContact)

        // sort messages by date
        //
//        let allContactMessagesT = selectedContact.messages.allObjects.sort(ChatsDatabase.sharedInstance.messageDateSort)

        // sort attachments by date
        //
        let allContactAttachmentsT = selectedContact.attachments.allObjects.sort { (a, b) -> Bool in
            let aAttachment = a as! ChatAttachment
            let bAttachment = b as! ChatAttachment

            return aAttachment.date.isLessThan(bAttachment.date)
        }

//        let allContactMessages = allContactMessagesT as! [ChatMessage]

        let allContactChatItems = selectedContact.messages.setByAddingObjectsFromSet(selectedContact.attachments as Set<NSObject>) // COMMENT THIS LINE TO FIX COMPILE ERROR IN AppDelegate

        let allContactChatItemsSorted = allContactChatItems.sort(chatsDatabase.messageDateSort) as! [ChatItem]
        
        messagesListViewController?.attachmentsToDisplay = allContactAttachmentsT as? [ChatAttachment]
        messagesListViewController?.attachmentsCollectionView.reloadData()
        messagesListViewController?.showMessages(allContactChatItemsSorted)
    }

    func chatIDsForSelectedRows(selectedRowIndexes : NSIndexSet) -> [Chat]
    {
        let index = selectedRowIndexes.firstIndex // no multiple selection

        guard let selectedContact = contactForRow(index) else { return [Chat]() }

        return selectedContact.chats.allObjects as! [Chat]

    }

    @IBAction func search(sender: NSSearchField) {

        NSLog("search for '\(sender.stringValue)'")

        if sender.stringValue == "" {
            
            searchMode = false
            searchedContacts = nil

            messagesListViewController?.clearMessages()
            tableView.reloadData()
            
        } else if sender.stringValue.characters.count >= 3 {

            let searchTerm = sender.stringValue

            chatsDatabase.searchChatsForString(searchTerm,
                afterDate: afterDateEnabled ? afterDate : nil,
                beforeDate: beforeDateEnabled ? beforeDate : nil,
                completion: { (matchingMessages) -> (Void) in
                    let matchingMessagesSorted = matchingMessages.sort(ChatsDatabase.sharedInstance.messageDateSort)
                    
                    self.messagesListViewController?.showMessages(matchingMessagesSorted, withHighlightTerm:searchTerm)
                    
                    self.searchedContacts = self.contactsFromMessages(matchingMessages)
                    self.searchMode = true
                    self.tableView.reloadData()
            })
            
//            let matchingMessages = ChatsDatabase.sharedInstance.searchChatsForString(searchTerm,
//                afterDate: afterDateEnabled ? afterDate : nil,
//                beforeDate: beforeDateEnabled ? beforeDate : nil)
//
//            let matchingMessagesSorted = matchingMessages.sort(ChatsDatabase.sharedInstance.messageDateSort)
//
//            messagesListViewController?.showMessages(matchingMessagesSorted, withHighlightTerm:searchTerm)
//
//            searchedContacts = contactsFromMessages(matchingMessages)
//            searchMode = true
            
        }
        
//        tableView.reloadData()
    }

    // restart a search once one of the date pickers has been changed
    //
    @IBAction func redoSearch(sender: NSObject) {
        if sender == afterDatePicker {
            afterDateEnabled = true
        }
        if sender == beforeDatePicker {
            beforeDateEnabled = true
        }
        
        search(searchField)
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
