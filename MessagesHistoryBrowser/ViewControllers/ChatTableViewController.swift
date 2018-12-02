//
//  ChatTableViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 25/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

let CountryPhonePrefixUserDefaultsKey = "CountryPhonePrefix"
let ShowDetailedSenderUserDefaultsKey = "ShowDetailedSender"
let ShowTerseTimeUserDefaultsKey = "ShowTerseTime"

class ChatTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var searchField: NSSearchField!
    @IBOutlet weak var afterDatePicker: NSDatePicker!
    @IBOutlet weak var beforeDatePicker: NSDatePicker!

    @IBOutlet weak var dbPopulateProgressIndicator: NSProgressIndicator!
    @IBOutlet weak var progressReportView: NSView!

    @objc dynamic var progress:Progress!

    var messagesListViewController:MessagesListViewController?

    var allKnownContacts = [ChatContact]()
    var allUnknownContacts = [ChatContact]()

    var messageFormatter = MessageFormatter()

    var showChatsFromUnknown = false

    var searchTerm:String?
    var searchedContacts:[ChatContact]?
    var searchedMessages:[ChatMessage]?
    var searchTermHasChanged = false

    var setupDBSucceeded = false

    @objc dynamic var beforeDateEnabled = false
    @objc dynamic var afterDateEnabled = false
    
    @objc dynamic var beforeDate = Date().addingTimeInterval(3600 * 24 * -7) // a week ago
    @objc dynamic var afterDate = Date().addingTimeInterval(3600 * 24 * -30) // a month ago

    var hasChatSelected:Bool {
        get { return tableView != nil && tableView.selectedRow >= 0 }
    }

    var showDetailedSenderUserDefault:Bool {
        return UserDefaults.standard.bool(forKey: ShowDetailedSenderUserDefaultsKey)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        // first connect to the Messages.app chats DB, and terminate if we can't
        //
        setupDBSucceeded = setupChatDatabase()

        let moc = MOCController.sharedInstance.managedObjectContext

        let appDelegate = NSApp.delegate as! AppDelegate
        appDelegate.chatTableViewController = self

        if let parentSplitViewController = parent as? NSSplitViewController {
            let secondSplitViewItem = parentSplitViewController.splitViewItems[1]

            messagesListViewController = secondSplitViewItem.viewController as? MessagesListViewController
        }

        NotificationCenter.default.addObserver(self, selector: #selector(ChatTableViewController.showUnknownContactsChanged(_:)), name: NSNotification.Name(rawValue: AppDelegate.ShowChatsFromUnknownNotification), object: nil)
//        NSNotificationCenter.defaultCenter().addObserver(self, selector: "phonePrefixChanged:", name: NSUserDefaultsDidChangeNotification, object: nil)

        UserDefaults.standard.addObserver(self, forKeyPath: CountryPhonePrefixUserDefaultsKey, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: ShowDetailedSenderUserDefaultsKey, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: ShowTerseTimeUserDefaultsKey, options: .new, context: nil)

        if Chat.numberOfChatsInContext(moc) == 0 {

            importMessagesFromOSXApp()

        } else if appDelegate.needDBReload { // CoreData DB load failed, rebuild the whole thing

            refreshChatHistory()

        } else {

            progressReportView.isHidden = true
            tableView.isHidden = false
            messagesListViewController?.view.isHidden = false

            allKnownContacts = ChatContact.allKnownContacts(moc)
            allUnknownContacts = ChatContact.allUnknownContacts(moc)
            tableView.reloadData()

        }


        ChatItemsFetcher.sharedInstance.completion = displayChats

    }

    override func viewDidAppear() {

        if !setupDBSucceeded {


            if #available(OSX 10.14, *) {

                let showAppPrivilegesSetupWindowController = NSStoryboard.main?.instantiateController(withIdentifier: "AccessPrivilegesDialog") as! NSWindowController

                NSApp.mainWindow?.beginSheet(showAppPrivilegesSetupWindowController.window!, completionHandler: { (_) in
                    NSApp.terminate(nil)
                })

            } else {
                let appDelegate = NSApp.delegate as! AppDelegate
                let chatsDBPath = appDelegate.chatsDBPath

                let alert = NSAlert()
                alert.messageText = String(format:NSLocalizedString("Couldn't open Messages.app database in\n%@", comment: ""), chatsDBPath)
                alert.informativeText = NSLocalizedString("Application can't run. Check if the database is accessible", comment: "")
                alert.alertStyle = .critical
                alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
                let _ = alert.runModal()
                NSApp.terminate(nil)
            }
        }

    }

    @objc func showUnknownContactsChanged(_ notification:Notification)
    {
        let appDelegate = NSApp.delegate as! AppDelegate
        showChatsFromUnknown = appDelegate.showChatsFromUnknown
        tableView.reloadData()
    }



    func contactForRow(_ row:Int) -> ChatContact?
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

    func numberOfRows(in tableView: NSTableView) -> Int
    {
        if searchTerm != nil {
            return searchedContacts?.count ?? 0
        }
        
        if showChatsFromUnknown {
            return allKnownContacts.count + allUnknownContacts.count
        }

        return allKnownContacts.count
    }


    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
    {
        guard let tableColumn = tableColumn else { return nil }

        let cellView = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as! NSTableCellView

        if let contact = contactForRow(row) {
            cellView.textField?.stringValue = contact.name
            if let cellImageView = cellView.imageView {

                ContactsMapProxy.sharedInstance.contactImage(contact.identifier) { (thumbnailImage, initialsPair) in
                    if let thumbnailImage = thumbnailImage {
                        let roundedThumbnailImage = roundCorners(thumbnailImage)
                        DispatchQueue.main.async { cellImageView.image = roundedThumbnailImage }
                    } else if let initialsPair = initialsPair {
                        // contact unknown for this cell, use initials to generate an image

                        let initials = "\(initialsPair.0)\(initialsPair.1)"

                        if let imageLabel = LabelToImage.stringToImage(initials) {
                            let roundImageLabel = roundCorners(imageLabel)
                            DispatchQueue.main.async { cellImageView.image = roundImageLabel }
                        }
                    } else {
                        DispatchQueue.main.async { cellImageView.image = nil }
                    }
                }

            }

        } else { // no contact for this row ? shouldn't happen
            NSLog("WARNING : no contact found for row \(row)")
            cellView.textField?.stringValue = "unknown"
            cellView.imageView?.image = nil
        }
        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification)
    {
        guard let index = tableView.selectedRowIndexes.first else { return } // no multiple selection

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

    func displayMessageListForContact(_ contact:ChatContact)
    {
//        chatsDatabase.collectMessagesForContact(contact)

        ChatItemsFetcher.sharedInstance.contact = contact

        ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()
    }

    func orderedMessagesForSelectedRow() -> (ChatContact, [ChatMessage])?
    {
        guard tableView.selectedRow >= 0 else { return nil }

        let index = tableView.selectedRow

        guard let selectedContact = contactForRow(index) else { return nil }

        let allContactChats = selectedContact.chats.allObjects as! [Chat]

        let allContactMessageArrays = allContactChats.compactMap { (chat) -> [ChatMessage]? in
            return chat.messages.allObjects as? [ChatMessage]
        }

//        let allContactMessages = allContactMessageArrays.reduce([ChatMessage]()) { (result, messageArray) -> [ChatMessage] in
//            return result + messageArray
//        }

        let allContactMessages = allContactMessageArrays.reduce([ChatMessage](), +)

        let allContactSortedMessages = allContactMessages.sorted { (messageA, messageB) -> Bool in
            return messageA.date < messageB.date
        }

        return (selectedContact, allContactSortedMessages)

    }

    // MARK: actions

    @IBAction func search(_ sender: NSSearchField) {

        NSLog("search for '\(sender.stringValue)'")

        searchTermHasChanged = true
        ChatItemsFetcher.sharedInstance.contact = nil

        if sender.stringValue == "" {
            
            searchTerm = nil
            searchedContacts = nil

            ChatItemsFetcher.sharedInstance.clearSearch()

            messagesListViewController?.showDetailedSender = showDetailedSenderUserDefault
            messagesListViewController?.clearMessages()
            messagesListViewController?.clearAttachments()
            tableView.reloadData()
            
        } else if sender.stringValue.count >= 3 && sender.stringValue != searchTerm {

            searchTerm = sender.stringValue

            ChatItemsFetcher.sharedInstance.searchTerm = sender.stringValue

            ChatItemsFetcher.sharedInstance.searchWithCompletionBlock()

        }
        
    }

    // restart a search once one of the date pickers has been changed
    //
    @IBAction func redoSearch(_ sender: NSObject)
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

    enum SaveError : Error {
        case dataConversionFailed
    }

    func saveContactChats(_ contact:ChatContact, atURL url:URL)
    {
        do {

            let messages = contact.messages.sorted(by: ChatItemsFetcher.sharedInstance.messageDateSort as! (NSFastEnumerationIterator.Element, NSFastEnumerationIterator.Element) -> Bool) as! [ChatMessage]

            let reducer = { (currentValue:String, message:ChatMessage) -> String in
                return currentValue + "\n" + self.messageFormatter.formatMessageAsString(message)
            }

            let allMessagesAsString = messages.reduce("", reducer)

            let tmpNSString = NSString(string: allMessagesAsString)

            if let data = tmpNSString.data(using: String.Encoding.utf8.rawValue) {

                FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)

            } else {
                throw SaveError.dataConversionFailed
            }

        } catch {
            NSLog("save failed")
        }
    }

    @IBAction func saveChat(_ sender:AnyObject)
    {
        guard let window = view.window else { return }

        guard let selectedContact = contactForRow(tableView.selectedRow) else { return }

        let savePanel = NSSavePanel()

        savePanel.nameFieldStringValue = selectedContact.name

        savePanel.beginSheetModal(for: window) { (modalResponse) -> Void in
            NSLog("do save at URL \(String(describing: savePanel.url))")

            guard let saveURL = savePanel.url else { return }

            self.saveContactChats(selectedContact, atURL: saveURL)
        }
    }

    // used as a completion block by ChatItemsFetcher
    //
    func displayChats(_ messages:[ChatItem], attachments:[ChatAttachment], matchedContacts:[ChatContact]?)
    {
//        print(__FUNCTION__)
        messagesListViewController?.hideAttachmentDisplayWindow()
        messagesListViewController?.attachmentsToDisplay = attachments
        messagesListViewController?.attachmentsCollectionView.reloadData()

        if searchTerm != nil { // Force showing detailed sender in messages list if there's a search term
            messagesListViewController?.showDetailedSender = true
        } else {
            messagesListViewController?.showDetailedSender = showDetailedSenderUserDefault
        }

        if messages.count > 0 {
            messagesListViewController?.showMessages(messages, withHighlightTerm: searchTerm)
        } else {
            messagesListViewController?.clearMessages()
            messagesListViewController?.clearAttachments()
        }


        if searchTermHasChanged {
            searchedContacts = matchedContacts?.sorted{ $0.name < $1.name }
            searchTermHasChanged = false
            tableView.reloadData()
        }
    }

    // recreate CoreData DB from original chats history DB
    //
    func refreshChatHistory() {

        let appDelegate = NSApp.delegate as! AppDelegate
        appDelegate.isRefreshingHistory = true

        setupProgressBeforeImport()

        guard let chatsDatabase = appDelegate.chatsDatabase else {
//            appDelegate.isRefreshingHistory = false
            return
        }

        MOCController.sharedInstance.clearAllCoreData()

        chatsDatabase.populate(progress, completion:{ () -> Void in

            self.completeImport()
//            MOCController.sharedInstance.save()
            appDelegate.isRefreshingHistory = false
        })
    }

    // MARK: - progress view

    // hide normal UI, show progress report
    //
    func setupProgressBeforeImport()
    {
        tableView.isHidden = true
        messagesListViewController?.view.isHidden = true
        progress = Progress(totalUnitCount: 10)
        progressReportView.isHidden = false
    }

    // hide progress report, restore normal UI
    //
    func completeImport()
    {
        if let currentProgress = Progress.current() {
            currentProgress.resignCurrent()
        }
        progressReportView.isHidden = true
        tableView.isHidden = false
        messagesListViewController?.view.isHidden = false

        allKnownContacts = ChatContact.allKnownContacts(MOCController.sharedInstance.managedObjectContext)
        allUnknownContacts = ChatContact.allUnknownContacts(MOCController.sharedInstance.managedObjectContext)
        tableView.reloadData()
    }

    func importMessagesFromOSXApp()
    {
        let appDelegate = NSApp.delegate as! AppDelegate

        appDelegate.isRefreshingHistory = true

        guard let chatsDatabase = appDelegate.chatsDatabase else {
            appDelegate.isRefreshingHistory = false
            return
        }

        setupProgressBeforeImport()
        
        chatsDatabase.populate(progress, completion:{ () -> Void in
            
            self.completeImport()
//            MOCController.sharedInstance.save()
            appDelegate.isRefreshingHistory = false
        })

    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
//        if let newValue = change?["new"] {
//            print("keyPath : \(keyPath) - new value : \(newValue)")
//        } else {
//            print("observeValueForKeyPath on NSUserDefaults : no new value found")
//        }

        // probably not a good idea from a usability point of view to trigger a re-import on pref change
        //
//        refreshChatHistory()

        guard let newValue = change?[NSKeyValueChangeKey.newKey] as? Bool else { return }

        if keyPath == ShowDetailedSenderUserDefaultsKey {
            messagesListViewController?.showDetailedSender = newValue
        } else if keyPath == ShowTerseTimeUserDefaultsKey {
            messagesListViewController?.showTerseTime = newValue
        }

    }

    func setupChatDatabase() -> Bool {

        let appDelegate = NSApp.delegate as! AppDelegate
        let chatsDBPath = appDelegate.chatsDBPath

        do {
            try appDelegate.chatsDatabase = ChatsDatabase(chatsDBPath:chatsDBPath)
        } catch let error {
            NSLog("DB init error : \(error)")
            return false
        }

        return true
    }
}
