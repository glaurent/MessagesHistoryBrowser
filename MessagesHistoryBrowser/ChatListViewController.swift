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

    override func viewDidLoad()
    {
        super.viewDidLoad()
        // Do view setup here.

        chatsDatabase = ChatsDatabase.sharedInstance

        outlineView.reloadData()

    }


// MARK: NSOutlineViewDataSource
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject
    {
        print("child index \(index) of item \(item)")

        if item == nil {
            let res = chatsDatabase.chatsSortedKeys[index]
            print("res : \(res)")
            return NSString(string: res) // REALLY have to return an NSString here, or we get memory corruptions. NSOutlineView doesn't like Swift Strings.
        }

        if let contactName = item as? String {
            if let chatsForContactName = chatsDatabase.chatsDictionnary[contactName] {
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
            if let chatsForContactName = chatsDatabase.chatsDictionnary[contactName] {
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
            return chatsDatabase.chatsDictionnary.keys.count
        }

        if let contactName = item as? String, chatsForContactName = chatsDatabase.chatsDictionnary[contactName] {
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
