//
//  MOCController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 26/12/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import CoreData

class MOCController: NSObject {

    public static let sharedInstance = MOCController()

    // MARK: - Core Data stack
    //
    // MOCController is the single owner of the Core Data stack. This avoids
    // relying on NSApp.delegate, which under the SwiftUI App lifecycle is
    // SwiftUI's own internal AppDelegate rather than our AppDelegate.
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "MessagesHistoryBrowser")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unresolved error \(error)")
            }
        }
        return container
    }()

    var managedObjectContext:NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    override init() {
    }

    func save()
    {
        let context = persistentContainer.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                NSLog("Error saving context: \(error)")
            }
        }
    }

    func clearAllCoreData()
    {
        MOCController.clearAllData(in: persistentContainer)
    }

    // Deletes every object in `container`'s store and tells its view context.
    //
    // Batch deletes run directly against the store and bypass the contexts, so
    // the view context would otherwise keep its registered objects as stale
    // zombies: rows already displayed keep showing old data, and faulting one
    // of them fails. The store is asked for the deleted object IDs, which are
    // merged into the view context as deletions; the objects it holds are
    // invalidated and its fetched results controllers see them go.
    //
    // Must be called on the main queue, the view context's queue.
    static func clearAllData(in container: NSPersistentContainer)
    {
        let viewContext = container.viewContext

        let fetchRequests: [NSFetchRequest<NSFetchRequestResult>] = [
            ChatContact.fetchRequest(),
            ChatAttachment.fetchRequest(),
            ChatMessage.fetchRequest(),
            Chat.fetchRequest(),
        ]

        var deletedObjectIDs = [NSManagedObjectID]()
        let context = container.newBackgroundContext()
        context.performAndWait {
            do {
                for fetchRequest in fetchRequests {
                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                    deleteRequest.resultType = .resultTypeObjectIDs
                    let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                    deletedObjectIDs.append(contentsOf: result?.result as? [NSManagedObjectID] ?? [])
                }
            } catch let error {
                NSLog("ERROR when clearing store : \(error)")
            }
        }

        // Only the objects the view context actually holds need merging; the
        // store may hold hundreds of thousands of rows the UI never touched.
        let registeredIDs = Set(viewContext.registeredObjects.map { $0.objectID })
        let idsToMerge = deletedObjectIDs.filter { registeredIDs.contains($0) }
        guard !idsToMerge.isEmpty else { return }

        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: idsToMerge], into: [viewContext])
    }

    func workerContext() -> NSManagedObjectContext
    {
        return persistentContainer.newBackgroundContext()
    }

}
