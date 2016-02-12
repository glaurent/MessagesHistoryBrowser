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

    lazy var moc = MOCController.sharedInstance.managedObjectContext

    var messageFormatter = MessageFormatter()

    var showChatsFromUnknown = false

    var searchTerm:String?
    var searchedContacts:[ChatContact]?
    var searchedMessages:[ChatMessage]?
    var searchTermHasChanged = false

    dynamic var beforeDateEnabled = false
    dynamic var afterDateEnabled = false
    
    dynamic var beforeDate = NSDate().dateByAddingTimeInterval(3600 * 24 * -7) // a week ago
    dynamic var afterDate = NSDate().dateByAddingTimeInterval(3600 * 24 * -30) // a month ago

    var hasChatSelected:Bool {
        get { return tableView != nil && tableView.selectedRow >= 0 }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        let appDelegate = NSApp.delegate as! AppDelegate
        appDelegate.chatTableViewController = self

        chatsDatabase = ChatsDatabase.sharedInstance

        if let parentSplitViewController = parentViewController as? NSSplitViewController {
            let secondSplitViewItem = parentSplitViewController.splitViewItems[1]

            messagesListViewController = secondSplitViewItem.viewController as? MessagesListViewController
        }

        NSNotificationCenter.defaultCenter().addObserver(self, selector: "showUnknownContactsChanged:", name: AppDelegate.ShowChatsFromUnknownNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "phonePrefixChanged:", name: NSUserDefaultsDidChangeNotification, object: nil)

//        progress.addObserver(self, forKeyPath: "localizedDescription", options: NSKeyValueObservingOptions.New, context: nil)

//        progress.addObserver(self, forKeyPath: "fractionCompleted", options: NSKeyValueObservingOptions.New, context: nil)

//        progressReportView.hidden = false

        progress.completedUnitCount = 0

        chatsDatabase.populate(progress, start: {
            () -> Void in
            self.progressReportView.hidden = false
            },
            completion: { () -> Void in

            MOCController.sharedInstance.save()

            self.progressReportView.hidden = true
            self.allKnownContacts = ChatContact.allKnownContactsInContext(self.moc)
            self.allUnknownContacts = ChatContact.allUnknownContactsInContext(self.moc)
            self.tableView.reloadData()

        })

        ChatItemsFetcher.sharedInstance.completion = displayChats

        if appDelegate.needDBReload {
            refreshChatHistory()
        }
    }

    func showUnknownContactsChanged(notification:NSNotification)
    {
        let appDelegate = NSApp.delegate as! AppDelegate
        showChatsFromUnknown = appDelegate.showChatsFromUnknown
        tableView.reloadData()
    }

    func contactForRow(row:Int) -> ChatContact?
    {
        
        guard (searchTerm != nil && row < searchedContacts!.count) || (showChatsFromUnknown && row < allKnownContacts.count + allUnknownContacts.count) || row < allKnownContacts.count else { return nil }
        
        var contact:ChatContact

        if searchTerm != nil {
            
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
        if searchTerm != nil {
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
            if let cellImageView = cellView.imageView, thumbnailImage = ContactsMap.sharedInstance.contactImage(contact.identifier) {
                let roundedThumbnailImage = roundCorners(thumbnailImage)
                cellImageView.image = roundedThumbnailImage
//              cellImageView.image = thumbnailImage
            }
        }
        
        return cellView
    }

    func tableViewSelectionDidChange(notification: NSNotification)
    {
        let index = tableView.selectedRowIndexes.firstIndex // no multiple selection

        if let selectedContact = contactForRow(index) {

            displayMessageListForContact(selectedContact)

        } else { // no contact selected, clean up

            if let searchTerm = searchTerm { // there is a search set, go back to full list of matching messages
                ChatItemsFetcher.sharedInstance.restoreSearchToAllContacts()
                messagesListViewController?.showMessages(ChatItemsFetcher.sharedInstance.matchingItems, withHighlightTerm: searchTerm)
            } else { // no search, clear all
                messagesListViewController?.clearAttachments()
                messagesListViewController?.clearMessages()
            }
        }
    }

    func displayMessageListForContact(contact:ChatContact)
    {
//        chatsDatabase.collectMessagesForContact(contact)

        ChatItemsFetcher.sharedInstance.contact = contact

        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
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

        searchTermHasChanged = true
        ChatItemsFetcher.sharedInstance.contact = nil

        if sender.stringValue == "" {
            
            searchTerm = nil
            searchedContacts = nil

            ChatItemsFetcher.sharedInstance.clearSearch()

            messagesListViewController?.detailedSender = false
            messagesListViewController?.clearMessages()
            messagesListViewController?.clearAttachments()
            tableView.reloadData()
            
        } else if sender.stringValue.characters.count >= 3 && sender.stringValue != searchTerm {

            searchTerm = sender.stringValue

            ChatItemsFetcher.sharedInstance.searchTerm = sender.stringValue

            ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()

        }
        
    }

    // restart a search once one of the date pickers has been changed
    //
    @IBAction func redoSearch(sender: NSObject)
    {
        if sender == afterDatePicker {
            afterDateEnabled = true
        } else if sender == beforeDatePicker {
            beforeDateEnabled = true
        }

        ChatItemsFetcher.sharedInstance.afterDate = afterDateEnabled ? afterDatePicker.dateValue : nil
        ChatItemsFetcher.sharedInstance.beforeDate = beforeDateEnabled ? beforeDatePicker.dateValue : nil

        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()

    }
    

//    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
//        print("\(__FUNCTION__) : \(change)")

//        if keyPath == "fractionCompleted" {
//            let newValue = change!["new"] as! NSNumber
//            dbPopulateProgressIndicator.doubleValue = newValue.doubleValue
//        }
//    }

    // MARK: file save

    enum SaveError : ErrorType {
        case dataConversionFailed
    }

    func saveContactChats(contact:ChatContact, atURL url:NSURL)
    {
        do {

            chatsDatabase.collectMessagesForContact(contact)

            let messages = contact.messages.sort(ChatItemsFetcher.sharedInstance.messageDateSort) as! [ChatMessage]

            let reducer = { (currentValue:String, message:ChatMessage) -> String in
                return currentValue + "\n" + self.messageFormatter.formatMessageAsString(message)
            }

            let allMessagesAsString = messages.reduce("", combine:reducer)

            let tmpNSString = NSString(string: allMessagesAsString)

            if let data = tmpNSString.dataUsingEncoding(NSUTF8StringEncoding) {

                NSFileManager.defaultManager().createFileAtPath(url.path!, contents: data, attributes: nil)

            } else {
                throw SaveError.dataConversionFailed
            }

        } catch {
            NSLog("save failed")
        }
    }

    @IBAction func saveChat(sender:AnyObject)
    {
        guard let window = view.window else { return }

        guard let selectedContact = contactForRow(tableView.selectedRow) else { return }

        let savePanel = NSSavePanel()

        savePanel.nameFieldStringValue = selectedContact.name

        savePanel.beginSheetModalForWindow(window) { (modalResponse) -> Void in
            NSLog("do save at URL \(savePanel.URL)")

            guard let saveURL = savePanel.URL else { return }

            self.saveContactChats(selectedContact, atURL: saveURL)
        }
    }

    // used as a completion block by ChatItemsFetcher
    //
    func displayChats(messages:[ChatItem], attachments:[ChatAttachment], matchedContacts:[ChatContact]?)
    {
//        print(__FUNCTION__)
        messagesListViewController?.hideAttachmentDisplayWindow()
        messagesListViewController?.attachmentsToDisplay = attachments
        messagesListViewController?.attachmentsCollectionView.reloadData()

        messagesListViewController?.detailedSender = searchTerm != nil

        if messages.count > 0 {
            messagesListViewController?.showMessages(messages, withHighlightTerm: searchTerm)
        } else {
            messagesListViewController?.clearMessages()
            messagesListViewController?.clearAttachments()
        }

        searchedContacts = matchedContacts?.sort{ $0.name < $1.name }

        if searchTermHasChanged {
            searchTermHasChanged = false
            tableView.reloadData()
        }
    }

    // recreate CoreData DB from original chats history DB
    //
    func refreshChatHistory() {

        // hide normal UI, show progress report
        //
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.tableView.hidden = true
            self.messagesListViewController?.view.hidden = true
            self.progress.completedUnitCount = 0
            self.progressReportView.hidden = false
        }

        let appDelegate = NSApp.delegate as! AppDelegate

        MOCController.sharedInstance.clearAllCoreData()

        ChatsDatabase.sharedInstance.populate(progress, start: {
            () -> Void in
            self.progressReportView.hidden = false
            }, completion:  { () -> Void in

                // hide progress report, restore normal UI
                //
                self.progressReportView.hidden = true
                self.tableView.hidden = false
                self.messagesListViewController?.view.hidden = false

                self.allKnownContacts = ChatContact.allKnownContactsInContext(self.moc)
                self.allUnknownContacts = ChatContact.allUnknownContactsInContext(self.moc)
                self.tableView.reloadData()

                appDelegate.isRefreshingHistory = false
                
                MOCController.sharedInstance.save()
        })
    }

    func phonePrefixChanged(userInfo:NSDictionary) {
        print("phone prefix changed - TODO") // TODO
//        refreshChatHistory()
    }


}
