//
//  Extensions.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 28/09/2026.
//  Copyright © 2026 Guillaume Laurent. All rights reserved.
//

import Foundation

let ShowDetailedSenderUserDefaultsKey = "ShowDetailedSender"
let ShowTerseTimeUserDefaultsKey = "ShowTerseTime"

extension String {
    func standardizingPath() -> String {
        return self.replacingOccurrences(of: "~", with: "/Users/" + NSUserName())
    }
}
