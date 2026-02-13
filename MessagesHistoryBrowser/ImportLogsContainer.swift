//
//  ImportLogsContainer.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 06/01/2022.
//  Copyright © 2022 Guillaume Laurent. All rights reserved.
//

import Foundation

struct ImportLogsContainer {
    static var logs = [String]()

    static func clear() {
        logs = [String]()
    }

    static func log(_ log: String) {
        logs.append("\(Date()) : \(log)")
    }

    static func allLogs() -> String {
        var res = ""
        for line in logs {
            res += line
            res += "\n"
        }
        return res
        // Looks more elegant, but is unfortunately way slower
//        logs.reduce("") { partialResult, line in
//            partialResult + "\n" + line
//        }
    }
}
