//
//  MessagesHistoryBrowserTests.swift
//  MessagesHistoryBrowserTests
//
//  Created by Guillaume Laurent on 27/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import XCTest
import Contacts
import CoreData
@testable import MessagesHistoryBrowser

class MessagesHistoryBrowserTests: XCTestCase {

    // Re-import clears the store with batch deletes, which bypass the
    // contexts. The view context must still learn that the objects it holds
    // are gone, otherwise the UI keeps stale rows and faulting one of them
    // fails. Uses a private in-memory SQLite store so the real data is untouched.
    func testClearingTheStoreInvalidatesObjectsHeldByTheViewContext() throws {
        let model = NSPersistentContainer(name: "MessagesHistoryBrowser").managedObjectModel
        let container = NSPersistentContainer(name: "MessagesHistoryBrowser", managedObjectModel: model)
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)

        let viewContext = container.viewContext
        viewContext.automaticallyMergesChangesFromParent = true

        // Seed one contact with a chat holding a message and an attachment,
        // all registered in the view context as a displaying UI would have them.
        let contact = ChatContact(managedObjectContext: viewContext, withName: "Test", withIdentifier: "test-id")
        let chat = Chat(managedObjectContext: viewContext, withContact: contact, withServiceName: "iMessage", withGUID: "guid", andRowID: 1)
        let message = ChatMessage(managedObjectContext: viewContext, withMessage: "hello", withDate: Date(), inChat: chat)
        let attachment = ChatAttachment(managedObjectContext: viewContext, withFileName: "~/file.jpg", withDate: Date(), inChat: chat)
        try viewContext.save()
        XCTAssertEqual(try viewContext.count(for: ChatMessage.fetchRequest()), 1)

        // Never the shared instance: that one would wipe the real store.
        MOCController(persistentContainer: container).clearAllCoreData()

        // The store is empty...
        XCTAssertEqual(try viewContext.count(for: ChatContact.fetchRequest()), 0)
        XCTAssertEqual(try viewContext.count(for: Chat.fetchRequest()), 0)
        XCTAssertEqual(try viewContext.count(for: ChatMessage.fetchRequest()), 0)
        XCTAssertEqual(try viewContext.count(for: ChatAttachment.fetchRequest()), 0)

        // ...and the view context marks the old objects deleted. (Core Data
        // keeps a deleted object registered until the context's next
        // turnover, so `isDeleted` — not `registeredObjects` — is the signal
        // the UI must check before using a reference it still holds.)
        for object in [contact, chat, message, attachment] as [NSManagedObject] {
            XCTAssertTrue(object.isDeleted,
                          "\(object.entity.name ?? "object") is not marked deleted after the store was cleared")
        }
    }

    // The import resolves chat handles to contacts with the Contacts
    // framework's phone number and email predicates. Those predicates only
    // work when the matched property is among the fetched keys, a mistake
    // that silently turns every contact into an "unknown" one, so check the
    // lookups against the real address book. Skipped when the test host has
    // no Contacts access.
    func testPhoneAndEmailLookupsResolveAddressBookContacts() throws {
        try XCTSkipUnless(CNContactStore.authorizationStatus(for: .contacts) == .authorized,
                          "Contacts access not granted to the test host")

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
        var phoneSamples = [(number: String, identifier: String)]()
        var emailSamples = [(email: String, identifier: String)]()

        try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, stop in
            if phoneSamples.count < 5, let phone = contact.phoneNumbers.first {
                phoneSamples.append((phone.value.stringValue, contact.identifier))
            }
            if emailSamples.count < 5, let email = contact.emailAddresses.first {
                emailSamples.append((email.value as String, contact.identifier))
            }
            if phoneSamples.count >= 5 && emailSamples.count >= 5 {
                stop.pointee = true
            }
        }
        try XCTSkipIf(phoneSamples.isEmpty && emailSamples.isEmpty, "address book has no phone numbers or emails to test with")

        var matchingPhoneIdentifiers = 0
        for sample in phoneSamples {
            let result = ContactsMap.sharedInstance.nameForPhoneNumber(sample.number)
            XCTAssertNotNil(result, "no contact resolved for phone number \(sample.number)")
            XCTAssertFalse(result?.0.isEmpty ?? true, "empty name for phone number \(sample.number)")
            if result?.1 == sample.identifier { matchingPhoneIdentifiers += 1 }
        }
        // A number can legitimately belong to several cards, so only require
        // that the resolved identifiers are, on the whole, the expected ones.
        if !phoneSamples.isEmpty {
            XCTAssertGreaterThan(matchingPhoneIdentifiers, 0, "phone lookups never returned the expected contact")
        }

        var matchingEmailIdentifiers = 0
        for sample in emailSamples {
            let result = ContactsMap.sharedInstance.nameForEmailAddress(sample.email)
            XCTAssertNotNil(result, "no contact resolved for email \(sample.email)")
            XCTAssertFalse(result?.0.isEmpty ?? true, "empty name for email \(sample.email)")
            if result?.1 == sample.identifier { matchingEmailIdentifiers += 1 }
        }
        if !emailSamples.isEmpty {
            XCTAssertGreaterThan(matchingEmailIdentifiers, 0, "email lookups never returned the expected contact")
        }

        XCTAssertNil(ContactsMap.sharedInstance.nameForPhoneNumber("+10000000000000"))
        XCTAssertNil(ContactsMap.sharedInstance.nameForEmailAddress("nobody-\(UUID().uuidString)@example.invalid"))
    }

    // Without an explicit requestAccess call, `.notDetermined` never becomes
    // `.authorized`: the fetch APIs just fail silently and every chat
    // resolves to "unknown" with no prompt ever shown. This exercises the
    // `.authorized` branch (the test host already has access, per the test
    // above) and confirms the call returns promptly rather than blocking
    // waiting on a prompt that will never come.
    func testRequestAccessIfNeededReturnsGrantedWhenAlreadyAuthorized() async throws {
        try XCTSkipUnless(CNContactStore.authorizationStatus(for: .contacts) == .authorized,
                          "Contacts access not granted to the test host")

        let granted = await ContactsMap.sharedInstance.requestAccessIfNeeded()

        XCTAssertTrue(granted)
    }

}
