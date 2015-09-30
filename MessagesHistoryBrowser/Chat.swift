//
//  Chat.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 27/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class Chat : NSObject {
    var contact = ""
    var guid = ""
    var rowID = 0

    init(withContact aContact:String, withGUID aGuid:String, andRowID aRowID:Int) {
        contact = aContact
        guid = aGuid
        rowID = aRowID
    }
}

