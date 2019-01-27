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

        let messageSpanClass = isFromMe ? "messageTextFromMe" : "messageText"

        let dateSpanClass = isFromMe ? "dateFromMe" : "date"

        let res = "<div class=\"message\"><span class=\"\(dateSpanClass)\">\(HTMLDateFormatter.shared.dateFormatter.string(from: date))</span> : <span class=\"\(messageSpanClass)\">\(nonEmptyContent)</span></div>\n"

        return res
    }
}

extension ChatAttachment : HTMLExportable {

    // name of folder in which attachments will be stored in HTML export
    //
    static let attachmentsFolderName = "attachments"

    func htmlString() -> String {

        let res:String

        let dateSpanClass = isFromMe ? "dateFromMe" : "date"

        if let fileName = standardizedFileName {

            let attachmentFileURL = URL(fileURLWithPath: fileName)

            let exportedAttachmentPath = ChatAttachment.attachmentsFolderName + "/" + attachmentFileURL.lastPathComponent

            if isImage() {
                res = "<div class=\"image\"><span class=\"\(dateSpanClass)\">\(HTMLDateFormatter.shared.dateFormatter.string(from: date))</span><img src=\"\(exportedAttachmentPath)\"></div>\n"
            } else {
                res = "<div class=\"attachment\"><span class=\"\(dateSpanClass)\">\(HTMLDateFormatter.shared.dateFormatter.string(from: date))</span><a href=\"file://\(exportedAttachmentPath)\">\(exportedAttachmentPath)</a></div>\n"
            }

        } else {

            res = "<div class=\"attachment\"><span class=\"\(dateSpanClass)\">\(HTMLDateFormatter.shared.dateFormatter.string(from: date))</span> : empty attachment</div>\n"

        }

        return res
    }

    func isImage() -> Bool {
        guard let fileName = standardizedFileName else { return false }

        do {
            let type = try NSWorkspace.shared.type(ofFile: fileName)
            let res = NSWorkspace.shared.type(type, conformsToType: String(kUTTypeImage))
            NSLog("isImage : \(fileName) - \(res)")
            return res
        } catch let error {
            NSLog("isImage : error \(error.localizedDescription)")
            return false
        }

    }

}
