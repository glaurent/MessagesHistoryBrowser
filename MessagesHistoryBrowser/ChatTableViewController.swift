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

    dynamic var progress:NSProgress!

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
//        NSNotificationCenter.defaultCenter().addObserver(self, selector: "phonePrefixChanged:", name: NSUserDefaultsDidChangeNotification, object: nil)

        NSUserDefaults.standardUserDefaults().addObserver(self, forKeyPath: "CountryPhonePrefix", options: .New, context: nil)

        if Chat.numberOfChatsInContext(moc) == 0 {

            importMessagesFromOSXApp()

        } else if appDelegate.needDBReload { // CoreData DB load failed, rebuild the whole thing

            refreshChatHistory()

        } else {

            progressReportView.hidden = true
            tableView.hidden = false
            messagesListViewController?.view.hidden = false

            allKnownContacts = ChatContact.allKnownContactsInContext(self.moc)
            allUnknownContacts = ChatContact.allUnknownContactsInContext(self.moc)
            tableView.reloadData()

        }


        ChatItemsFetcher.sharedInstance.completion = displayChats

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

//        print("\(__FUNCTION__) : row \(row) - contact \(contact.name)")

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
            } else {
                // contact unknown for this cell
                cellView.imageView?.image = nil
            }
        } else { // shouldn't happen
            cellView.textField?.stringValue = "unknown"
            cellView.imageView?.image = nil
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


        if searchTermHasChanged {
            searchedContacts = matchedContacts?.sort{ $0.name < $1.name }
            searchTermHasChanged = false
            tableView.reloadData()
        }
    }

    // recreate CoreData DB from original chats history DB
    //
    func refreshChatHistory() {

        setupProgressBeforeImport()

        let appDelegate = NSApp.delegate as! AppDelegate

        MOCController.sharedInstance.clearAllCoreData()

        chatsDatabase.populate(progress, completion:{ () -> Void in

            self.completeImport()
            appDelegate.isRefreshingHistory = false

            MOCController.sharedInstance.save()
        })
    }

    // MARK: - progress view

    // hide normal UI, show progress report
    //
    func setupProgressBeforeImport()
    {
        tableView.hidden = true
        messagesListViewController?.view.hidden = true
        progress = NSProgress(totalUnitCount: 10)
        progressReportView.hidden = false
    }

    // hide progress report, restore normal UI
    //
    func completeImport()
    {
        if let currentProgress = NSProgress.currentProgress() {
            currentProgress.resignCurrent()
        }
        progressReportView.hidden = true
        tableView.hidden = false
        messagesListViewController?.view.hidden = false

        allKnownContacts = ChatContact.allKnownContactsInContext(self.moc)
        allUnknownContacts = ChatContact.allUnknownContactsInContext(self.moc)
        tableView.reloadData()
    }

    func importMessagesFromOSXApp()
    {
        setupProgressBeforeImport()
        
        chatsDatabase.populate(progress, completion:{ () -> Void in
            
            self.completeImport()
            MOCController.sharedInstance.save()
            
        })

    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
//        if let newValue = change?["new"] {
//            print("keyPath : \(keyPath) - new value : \(newValue)")
//        } else {
//            print("observeValueForKeyPath on NSUserDefaults : no new value found")
//        }

        refreshChatHistory()
    }

}
