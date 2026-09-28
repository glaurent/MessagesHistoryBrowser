//
//  MessagesHistoryBrowserTests.swift
//  MessagesHistoryBrowserTests
//
//  Created by Guillaume Laurent on 27/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import XCTest
import Contacts
@testable import MessagesHistoryBrowser

class MessagesHistoryBrowserTests: XCTestCase {

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

}
