//
//  ChatsDatabase.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 04/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import AddressBook
import SQLite

class ChatsDatabase: NSObject {

    static let sharedInstance = ChatsDatabase()

    let chatsDBPath = "/Users/glaurent/tmp/chat.db"

    var contactsPhoneNumber:ContactsMap! // want delayed init

    var allChats = [Chat]()

    var chatsDictionnary = [String : [Chat]]()

    var chatsSortedKeys = [String]()

    var db:Connection!

    override init() {


        do {
            contactsPhoneNumber = ContactsMap.sharedInstance

            db = try Connection(chatsDBPath, readonly:true)

            super.init()

            //
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
            
        } catch {
            super.init()
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

    func messagesForChatID(chatID:Chat) -> [ChatMessage]
    {
        var res:[ChatMessage] = []

        let messagesTable  = Table("message")
        let isFromMeColumn = Expression<Bool>("is_from_me")
        let textColumn     = Expression<String>("text")
        let dateColumn     = Expression<Int>("date")

        let chatHandleJoinTable = Table("chat_handle_join")
        let handleIdColumn      = Expression<Int>("handle_id")
        let chatIdColumn        = Expression<Int>("chat_id")

        let chatTable   = Table("chat")
        let rowIDColumn = Expression<Int>("ROWID")
        let guidColumn  = Expression<String>("guid")

        let chatIDQuery = db.prepare(chatTable.select(rowIDColumn).filter(guidColumn == chatID.guid))
        var allRowIDs = [Int]()
        for row in chatIDQuery {
            allRowIDs.append(row.get(rowIDColumn))
        }


        let handleIDQuery = db.prepare(chatHandleJoinTable.select(handleIdColumn).filter(allRowIDs.contains(chatIdColumn)))
        var allHandleIDs = [Int]()
        for row in handleIDQuery {
            allHandleIDs.append(row.get(handleIdColumn))
        }

        let query = db.prepare(messagesTable.select(isFromMeColumn, textColumn, dateColumn).filter(allHandleIDs.contains(handleIdColumn)))

        for messageData in query {
            let messageContent = messageData[textColumn]
            let dateInt = messageData[dateColumn]
            let dateTimeInterval = NSTimeInterval(dateInt)
            let messageDate = NSDate(timeIntervalSinceReferenceDate: dateTimeInterval)
//            NSLog("message : \(messageContent)")
            res.append(ChatMessage(message:messageContent, date:messageDate))
        }

        return res

//        let aChatMessage = ChatMessage(message:"foobar", date:NSDate())
//        
//        return [aChatMessage]
    }

}
