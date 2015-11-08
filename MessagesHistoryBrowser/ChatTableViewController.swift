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

    @IBOutlet weak var dbPopulateProgressIndicator: NSProgressIndicator!
    @IBOutlet weak var progressReportView: NSView!

    dynamic var progress:NSProgress = NSProgress(totalUnitCount: 700)

    var chatsDatabase:ChatsDatabase!

    var messagesListViewController:MessagesListViewController?

    var allKnownContacts = [ChatContact]()
    var allUnknownContacts = [ChatContact]()

    lazy var moc = (NSApp.delegate as! AppDelegate).managedObjectContext

    var messageFormatter = MessageFormatter()

    var showChatsFromUnknown = false
    
    var searchMode = false
    var searchedContacts:[ChatContact]?
    var searchedMessages:[ChatMessage]?

    dynamic var beforeDateEnabled = false
    dynamic var afterDateEnabled = false
    
    dynamic var beforeDate = NSDate()
    dynamic var afterDate = NSDate()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        chatsDatabase = ChatsDatabase.sharedInstance

        if let parentSplitViewController = parentViewController as? NSSplitViewController {
            let secondSplitViewItem = parentSplitViewController.splitViewItems[1]

            messagesListViewController = secondSplitViewItem.viewController as? MessagesListViewController
        }

        NSNotificationCenter.defaultCenter().addObserver(self, selector: "showUnknownContactsChanged:", name: AppDelegate.ShowChatsFromUnknownNotification, object: nil)

//        progress.addObserver(self, forKeyPath: "localizedDescription", options: NSKeyValueObservingOptions.New, context: nil)

//        progress.addObserver(self, forKeyPath: "fractionCompleted", options: NSKeyValueObservingOptions.New, context: nil)

        chatsDatabase.populate(progress, completion: { () -> Void in
                self.progressReportView.hidden = true
                self.allKnownContacts = ChatContact.allKnownContactsInContext(self.moc)
                self.allUnknownContacts = ChatContact.allUnknownContactsInContext(self.moc)
                self.tableView.reloadData()
        })

    }

    func showUnknownContactsChanged(notification:NSNotification)
    {
        let appDelegate = NSApp.delegate as! AppDelegate
        showChatsFromUnknown = appDelegate.showChatsFromUnknown
        tableView.reloadData()
    }

    func contactForRow(row:Int) -> ChatContact?
    {
        
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

        if let selectedContact = contactForRow(index) {


            if (searchMode) {

                if let searchedMessages = searchedMessages {

                    let allContactMessages = searchedMessages.filter({ (message) -> Bool in
                        return message.contact == selectedContact
                    })

                    messagesListViewController?.showMessages(allContactMessages)
                }

            } else {

                chatsDatabase.collectMessagesForContact(selectedContact)

                // sort attachments by date
                //
                let allContactAttachmentsT = selectedContact.attachments.allObjects.sort(ChatsDatabase.sharedInstance.messageDateSort)

                let allContactChatItems = selectedContact.messages.setByAddingObjectsFromSet(selectedContact.attachments as Set<NSObject>) // COMMENT THIS LINE TO FIX COMPILE ERROR IN AppDelegate

                let allContactChatItemsSorted = allContactChatItems.sort(chatsDatabase.messageDateSort) as! [ChatItem]
                
                messagesListViewController?.attachmentsToDisplay = allContactAttachmentsT as? [ChatAttachment]
                messagesListViewController?.attachmentsCollectionView.reloadData()
                messagesListViewController?.showMessages(allContactChatItemsSorted)
            }

        } else {

            if (searchMode) {
                if let searchedMessages = searchedMessages {
                    messagesListViewController?.showMessages(searchedMessages)
                }
            } else {
                messagesListViewController?.showMessages([ChatMessage]())
            }
        }
    }

    // MARK: actions

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
                    self.searchedMessages = matchingMessagesSorted
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


//    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
//        print("\(__FUNCTION__) : \(change)")

//        if keyPath == "fractionCompleted" {
//            let newValue = change!["new"] as! NSNumber
//            dbPopulateProgressIndicator.doubleValue = newValue.doubleValue
//        }
//    }

}
