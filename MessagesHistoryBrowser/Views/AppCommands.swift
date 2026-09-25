//
//  AppCommands.swift
//  MessagesHistoryBrowser
//
//  Menu bar commands
//

import SwiftUI


struct AppCommands: Commands {
    // @Environment(\.openWindow) var openWindow  // Only available in macOS 13+
    @FocusedValue(\.selectedContact) var selectedContact
    @FocusedValue(\.appState) var appState
    @FocusedValue(\.refreshChatHistory) var refreshChatHistory
    
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                // Sparkle integration would go here
            }
        }
        
        // Inject into the existing File menu rather than creating a second one.
        // Replacing the default New/Open group (unused by this non-document app)
        // keeps everything in a single File menu.
        CommandGroup(replacing: .newItem) {
            Button("Refresh Chat History") {
                refreshChatHistory?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refreshChatHistory == nil || (appState?.isRefreshingHistory ?? false))

            Divider()

            Button("Export Chat to JSON") {
                exportToJSON()
            }
            .disabled(selectedContact == nil)

            Button("Export Chat to HTML") {
                exportToHTML()
            }
            .disabled(selectedContact == nil)

            Divider()

            Button("Save...") {
                saveChat()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(selectedContact == nil)
        }
    }
    
    // MARK: - Data helpers

    // The selected contact belongs to the main viewContext and these commands run
    // on the main queue, so reading its relationships here is safe. All managed
    // object access happens up front, before the (async) save panel completes.

    private func orderedMessages(for contact: ChatContact) -> [ChatMessage] {
        let messages = (contact.messages.allObjects as? [ChatMessage]) ?? []
        return messages.sorted { $0.dateNanoseconds < $1.dateNanoseconds }
    }

    private func orderedChatItems(for contact: ChatContact) -> [ChatItem] {
        let messages = (contact.messages.allObjects as? [ChatItem]) ?? []
        let attachments = (contact.attachments.allObjects as? [ChatItem]) ?? []
        return (messages + attachments).sorted { $0.dateNanoseconds < $1.dateNanoseconds }
    }

    // MARK: - Export actions

    private func exportToJSON() {
        guard let contact = selectedContact else { return }

        // Build the export payload up front (main-context access).
        let messagesAsDicts = orderedMessages(for: contact).map { $0.toJSONConvertibleDict() }
        let dict: [String: Any] = ["contact": contact.name, "messages": messagesAsDicts]
        let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = contact.name + ".json"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url, let jsonData = jsonData else { return }
            do {
                try jsonData.write(to: url)
            } catch {
                NSLog("error while exporting to JSON : \(error.localizedDescription)")
            }
        }
    }

    private func exportToHTML() {
        guard let contact = selectedContact else { return }

        let contactName = contact.name
        let chatItems = orderedChatItems(for: contact)

        // Assemble the HTML document and gather attachment source paths up front,
        // so the async completion touches no managed objects.
        var htmlData = Data()
        let htmlPreamble = """
<!DOCTYPE html>
<html>
<head>
    <link rel="stylesheet" href="messagesStyle.css">
    <meta charset="UTF-8">
    <title>Chat with \(contactName)</title>
</head>
<body>
"""
        htmlData.append(htmlPreamble.data(using: .utf8)!)
        for chatItem in chatItems {
            guard let htmlExportable = chatItem as? HTMLExportable else { continue }
            if let data = htmlExportable.htmlString().data(using: .utf8) {
                htmlData.append(data)
            }
        }
        htmlData.append("</body>\n</html>".data(using: .utf8)!)

        var attachmentSourcePaths = [String]()
        var hasICloudStoredAttachments = false
        for attachment in chatItems.compactMap({ $0 as? ChatAttachment }) {
            if attachment.fileName?.hasSuffix(AppDelegate.iCloudStoredAttachmentExtension) ?? false {
                hasICloudStoredAttachments = true
            }
            if let path = attachment.standardizedFileName {
                attachmentSourcePaths.append(path)
            }
        }

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = contactName

        savePanel.begin { response in
            guard response == .OK, let baseFolderURL = savePanel.url else { return }

            var missingAttachments = [String]()

            do {
                // Main folder + index.html
                try? FileManager.default.createDirectory(at: baseFolderURL, withIntermediateDirectories: false, attributes: nil)
                let indexFileURL = baseFolderURL.appendingPathComponent("index.html")
                try htmlData.write(to: indexFileURL)

                // Attachments folder + copies
                let attachmentsFolderURL = baseFolderURL.appendingPathComponent(ChatAttachment.attachmentsFolderName)
                try? FileManager.default.createDirectory(at: attachmentsFolderURL, withIntermediateDirectories: false, attributes: nil)

                for sourcePath in attachmentSourcePaths {
                    let originURL = URL(fileURLWithPath: sourcePath)
                    let destinationURL = attachmentsFolderURL.appendingPathComponent(originURL.lastPathComponent)
                    do {
                        try FileManager.default.copyItem(at: originURL, to: destinationURL)
                    } catch {
                        NSLog("HTMLExport : couldn't copy \(sourcePath) : \(error.localizedDescription)")
                        missingAttachments.append(sourcePath)
                    }
                }

                // Copy the stylesheet from the app bundle
                if let cssURLInBundle = Bundle.main.url(forResource: "messagesStyle", withExtension: "css") {
                    let destinationURL = baseFolderURL.appendingPathComponent(cssURLInBundle.lastPathComponent)
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.copyItem(at: cssURLInBundle, to: destinationURL)
                } else {
                    NSLog("HTMLExport : ERROR couldn't find CSS in bundle")
                }
            } catch {
                NSLog("error while exporting to HTML : \(error.localizedDescription)")
            }

            if !missingAttachments.isEmpty || hasICloudStoredAttachments {
                displayAttachmentWarning(missingAttachments, attachmentsInICloud: hasICloudStoredAttachments)
            }
        }
    }

    private func saveChat() {
        guard let contact = selectedContact else { return }

        // Save a plain-text transcript of the conversation.
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let transcript = orderedMessages(for: contact).map { message -> String in
            let sender = message.isFromMe ? "Me" : contact.name
            return "[\(dateFormatter.string(from: message.date))] \(sender): \(message.content ?? "")"
        }.joined(separator: "\n")

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = contact.name + ".txt"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try transcript.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("error while saving chat : \(error.localizedDescription)")
            }
        }
    }

    private func displayAttachmentWarning(_ missingAttachments: [String], attachmentsInICloud: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.messageText = NSLocalizedString("Missing chat attachments", comment: "")

        if attachmentsInICloud {
            alert.informativeText = NSLocalizedString("Some attachments are stored in iCloud. Request their download from Messages.app to include them.", comment: "")
        } else {
            alert.informativeText = NSLocalizedString("The following attachments were not found:", comment: "") + "\n\n" + missingAttachments.joined(separator: "\n")
        }

        alert.runModal()
    }
}

// Focused values for menu commands
struct SelectedContactKey: FocusedValueKey {
    typealias Value = ChatContact
}

struct AppStateKey: FocusedValueKey {
    typealias Value = AppState
}

struct RefreshChatHistoryKey: FocusedValueKey {
    typealias Value = () -> Void
}


extension FocusedValues {
    var selectedContact: ChatContact? {
        get { self[SelectedContactKey.self] }
        set { self[SelectedContactKey.self] = newValue }
    }
    
    var appState: AppState? {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }

    var refreshChatHistory: (() -> Void)? {
        get { self[RefreshChatHistoryKey.self] }
        set { self[RefreshChatHistoryKey.self] = newValue }
    }
}
