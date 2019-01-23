//
//  HTMLExport.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 22/01/2019.
//  Copyright © 2019 Guillaume Laurent. All rights reserved.
//

import Foundation
import Cocoa

protocol HTMLExportable {
    func htmlString() -> String
}

struct HTMLDateFormatter {
    var dateFormatter = DateFormatter()

    static var shared:HTMLDateFormatter = HTMLDateFormatter()

    init() {
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
    }
}

extension ChatMessage : HTMLExportable {

    func htmlString() -> String {

        let nonEmptyContent = content ?? "<empty>"

        let res = "<div class=\"message\"><span class=\"date\">\(HTMLDateFormatter.shared.dateFormatter.string(from: date))</span> : <span class=\"messageText\">\(nonEmptyContent)</span></div>\n"

        return res
    }
}

extension ChatAttachment : HTMLExportable {

    func htmlString() -> String {

        let res:String

        if let fileName = fileName {

            if isImage() {
                res = "<div class=\"image\"><span class=\"date\">\(HTMLDateFormatter.shared.dateFormatter.string(from: date))</span><img src=\"\(fileName)\"></div>\n"
            } else {
                res = "<div class=\"attachment\"><span class=\"date\">\(HTMLDateFormatter.shared.dateFormatter.string(from: date))</span><a href=\"file://\(fileName)\">\(fileName)</a></div>\n"
            }

        } else {

            res = "<div class=\"attachment\"><span class=\"date\">\(HTMLDateFormatter.shared.dateFormatter.string(from: date))</span> : empty attachment</div>\n"

        }

        return res
    }

    func isImage() -> Bool {
        guard let fileName = fileName else { return false }

        do {
            let type = try NSWorkspace.shared.type(ofFile: fileName)
            return NSWorkspace.shared.type(type, conformsToType: String(kUTTypeImage))
        } catch {
            return false
        }

    }

}
