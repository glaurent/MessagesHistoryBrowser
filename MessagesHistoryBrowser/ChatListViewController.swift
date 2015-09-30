//
//  ChatListViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 20/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import AddressBook
import SQLite

class ChatListViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {

    @IBOutlet weak var outlineView: NSOutlineView!


    var contactsPhoneNumber:ContactsMap! // want delayed init

    var allChats = [Chat]()

    var chatsDictionnary = [String : [Chat]]()

    var chatsSortedKeys = [String]()

    override func viewDidLoad()
    {
        super.viewDidLoad()
        // Do view setup here.

        do {


            contactsPhoneNumber = ContactsMap.sharedInstance

            let db = try Connection("/Users/glaurent/tmp/chat.db", readonly:true)

            let chats = Table("chat")

            let chatRowIDColumn = Expression<Int>("ROWID")
            let chatGUIDColumn = Expression<String>("guid")
            let serviceNameColumn = Expression<String>("service_name")
            let chatIdentifierColumn = Expression<String>("chat_identifier")

            // Iterate over all chats
            //
            for chatData in db.prepare(chats.select(chatRowIDColumn, chatGUIDColumn, serviceNameColumn, chatIdentifierColumn)) {

                let guid = chatData[chatGUIDColumn]
                let rowID = chatData[chatRowIDColumn]
                let identifier = chatData[chatIdentifierColumn]
                let serviceName = chatData[serviceNameColumn]

                let chatContactName = contactNameForIdentifier(identifier, service:serviceName)

                let chat = Chat(withContact:chatContactName, withGUID: guid, andRowID: rowID)

                NSLog("chat : %@ \tcontact : %@\trowId: %d", chat.guid, chatContactName, chat.rowID)

                allChats.append(chat)

                if chatsDictionnary[chat.contact] != nil {
                    chatsDictionnary[chat.contact]!.append(chat)
                } else {
                    chatsDictionnary[chat.contact] = [chat]
                }

                
            }

            chatsSortedKeys = chatsDictionnary.keys.sort()

            outlineView.reloadData()

        } catch {
            NSLog("%@ error", __FUNCTION__)
        }

    }

    func contactNameForIdentifier(identifier:String, service serviceName:String) -> String
    {

        if serviceName == "AIM" || serviceName == "Jabber" {

            if let chatContactName = contactsPhoneNumber.nameForInstantMessageAddress(identifier) {
                return chatContactName
            }

        } else if serviceName == "iMessage" {

            // check if identifier contains a '@'
            if identifier.characters.contains("@") {
                if let chatContactName = contactsPhoneNumber.nameForEmailAddress(identifier) {
                    return chatContactName
                }
            } else if let chatContactName = contactsPhoneNumber.nameForPhoneNumber(identifier) {
                return chatContactName
            } else {
                return identifier
            }
        }

        return identifier
    }

// MARK: NSOutlineViewDataSource
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject
    {
        print("child index \(index) of item \(item)")

        if item == nil {
            let res = chatsSortedKeys[index]
            print("res : \(res)")
            return NSString(string: res)
        }

        if let contactName = item as? String {
            if let chatsForContactName = chatsDictionnary[contactName] {
                let chat = chatsForContactName[index]
                print("return chat \(chat.guid)")
                return chat
            }
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
        print("item \(item) isExpandable")

        if let contactName = item as? String {
            if let chatsForContactName = chatsDictionnary[contactName] {
                return chatsForContactName.count > 0 // should be always true in this case anyway
            } else {
                return false
            }
        }

        return false
    }

    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int
    {
        print("number of children of item \(item)")

        if item == nil {
//            return 5
            return chatsDictionnary.keys.count
        }

        if let contactName = item as? String, chatsForContactName = chatsDictionnary[contactName] {
            return chatsForContactName.count
        }

        return 1
    }

    // MARK: NSOutlineViewDelegate
    func outlineView(outlineView: NSOutlineView, viewForTableColumn: NSTableColumn?, item: AnyObject) -> NSView? {

        let view = outlineView.makeViewWithIdentifier("Chats", owner: self) as! NSTableCellView
        if let textField = view.textField {
            if let itemString = item as? String {
                textField.stringValue = itemString
            } else if let itemChat = item as? Chat {
                textField.stringValue = "chat GUID : \(itemChat.guid)"
            }
        }
        return view
    }

}
