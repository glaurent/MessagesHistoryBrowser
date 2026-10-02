//
//  ContactsPhoneNumberList.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 26/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import Contacts

class ContactsMap {

//    let countryPhonePrefix = "+33"
    var countryPhonePrefix:String

    static let sharedInstance = ContactsMap()

    let contactStore = CNContactStore()

    // Keys needed to display a contact's name (nickname first, else the
    // formatter's full name). Requested with every lookup, so the name comes
    // out of the same fetch as the match instead of a second round trip to
    // the contacts daemon.
    private let nameKeys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactNicknameKey as CNKeyDescriptor]

    // The phone number and email predicates do their matching on the fetched
    // contacts, so the matched property itself must be among the keys, or the
    // framework logs "A property was not requested when contact was fetched"
    // and returns nothing.
    private lazy var phoneLookupKeys: [CNKeyDescriptor] = nameKeys + [CNContactPhoneNumbersKey as CNKeyDescriptor]
    private lazy var emailLookupKeys: [CNKeyDescriptor] = nameKeys + [CNContactEmailAddressesKey as CNKeyDescriptor]

    // Instant-message handles have no predicate in the Contacts framework, so
    // they are read once, on first use, into this map (handle -> name and
    // contact identifier). Previously every AIM/Jabber chat enumerated the
    // whole address book.
    private lazy var instantMessageAddressMap: [String: (name: String, identifier: String)] = {
        var map = [String: (name: String, identifier: String)]()
        let request = CNContactFetchRequest(keysToFetch: nameKeys + [CNContactInstantMessageAddressesKey as CNKeyDescriptor])
        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                for labeledValue in contact.instantMessageAddresses {
                    let handle = labeledValue.value.username
                    // Keep the first contact found, as the former enumerate-and-stop did.
                    if map[handle] == nil {
                        map[handle] = (self.displayName(for: contact) ?? handle, contact.identifier)
                    }
                }
            }
        } catch let error {
            NSLog("\(#function) : error while enumerating contacts : \(error.localizedDescription)")
        }
        return map
    }()

    var progress:Progress?

    let contactFormatter = CNContactFormatter()

    init() {
        countryPhonePrefix = "+1"
        contactFormatter.style = .fullName
    }

    // Requests Contacts access if the user has never been asked, awaiting the
    // system's one-time permission prompt. Must be called (and its result
    // acted on) before the first lookup of an import: `authorizationStatus`
    // starts at `.notDetermined` on a fresh install, and simply calling the
    // fetch APIs without requesting access first fails silently — every chat
    // resolves to "unknown" with no prompt ever shown and no explanation.
    //
    // Returns whether the app can use the Contacts framework: already
    // authorized, newly granted, or not (denied, restricted, or the user
    // dismissed the prompt) — in which case every lookup below fails, so the
    // caller should tell the user why their contacts aren't being resolved.
    func requestAccessIfNeeded() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return true

        case .notDetermined:
            return await withCheckedContinuation { continuation in
                contactStore.requestAccess(for: .contacts) { granted, error in
                    if let error = error {
                        NSLog("\(#function) : error requesting Contacts access : \(error.localizedDescription)")
                    }
                    continuation.resume(returning: granted)
                }
            }

        case .denied, .restricted:
            return false

        @unknown default:
            return false
        }
    }

    func nameForPhoneNumber(_ phoneNumber:String) -> (String, String)? {

        let cnPhoneNumber = CNPhoneNumber(stringValue: phoneNumber)
        let predicateForPhoneNumber = CNContact.predicateForContacts(matching: cnPhoneNumber)

        do {

            let contacts = try contactStore.unifiedContacts(matching: predicateForPhoneNumber, keysToFetch: phoneLookupKeys)

            if let contact = contacts.first {
                let contactName = displayName(for: contact) ?? "<unknown> \(phoneNumber)"
                return (contactName, contact.identifier)
            } else {
                NSLog("\(#function) : couldn't find contact for this phone number \(phoneNumber))")
                return nil
            }

        } catch let error {
            NSLog("\(#function) : error while searching for \(phoneNumber)) - error \(error.localizedDescription)")
            return nil
        }

    }

    func nameForInstantMessageAddress(_ imAddressToSearch:String) -> (String, String)?
    {
        guard let match = instantMessageAddressMap[imAddressToSearch] else { return nil }
        return (match.name, match.identifier)
    }

    func nameForEmailAddress(_ emailAddressToSearch:String) -> (String, String)? {

        // A predicate lookup, like the phone number one, instead of a scan of
        // the whole address book for every chat.
        let predicateForEmail = CNContact.predicateForContacts(matchingEmailAddress: emailAddressToSearch)

        do {
            let contacts = try contactStore.unifiedContacts(matching: predicateForEmail, keysToFetch: emailLookupKeys)

            guard let contact = contacts.first else { return nil }
            return (displayName(for: contact) ?? emailAddressToSearch, contact.identifier)

        } catch let error {
            NSLog("\(#function) : error while searching for \(emailAddressToSearch) - error \(error.localizedDescription)")
            return nil
        }
    }

    // Nickname if set, otherwise the formatter's full name. `contact` must
    // have been fetched with `nameKeys`.
    private func displayName(for contact: CNContact) -> String? {
        if contact.nickname != "" {
            return contact.nickname
        }
        return contactFormatter.string(from: contact)
    }

    private func formattedContactName(_ contactIdentifier:String) -> String? {

        if let contact = try? contactStore.unifiedContact(withIdentifier: contactIdentifier, keysToFetch: [CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactNicknameKey as CNKeyDescriptor]) {

            if contact.nickname != "" {
                return contact.nickname
            }
            return contactFormatter.string(from: contact)
        } else {
            return nil
        }

//        let firstName = contact.givenName
//        let lastName = contact.familyName
//        return "\(firstName) \(lastName)"
    }

    // returns contact image or pair of initials if no image is found, or nil if contact is unknown
    //
    func contactImage(_ contactIdentifier:String) -> (NSImage?, (String, String)?) {
        do {
            let contact = try contactStore.unifiedContact(withIdentifier: contactIdentifier, keysToFetch:[CNContactImageDataKey as CNKeyDescriptor, CNContactThumbnailImageDataKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor])
            // The thumbnail is pre-sized by the Contacts daemon (roughly
            // 100-160px) and is all this app ever displays (at 32pt), so
            // prefer it: the full-size `imageData` can be several megabytes,
            // and both keys are transferred over IPC from the daemon whether
            // used or not, so there's no cost to trying the smaller one first.
            if let imageData = contact.thumbnailImageData ?? contact.imageData {
                return (NSImage(data: imageData), nil)
            } else {

                let firstNameInitial = String(contact.givenName.first ?? Character(" "))
                let lastNameInitial = String(contact.familyName.first ?? Character(" "))
                return (nil, (firstNameInitial, lastNameInitial))

//                // get a bitmap of the contact's initials (like in Contacts.app)
//                let firstName = contact.givenName
//                let lastName = contact.familyName
//
//                var initials = ""
//
//                if firstName.count > 0 {
//                    initials = initials + "\(firstName.first!)"
//                }
//                if lastName.count > 0 {
//                    initials = initials + "\(lastName.first!)"
//                }
//
//                if let imageLabel = LabelToImage.stringToImage(initials) {
//                    return imageLabel
//                }
            }
        } catch {
            NSLog("\(#function) : Couldn't get contact with identifier \"\(contactIdentifier)\"")
            return (nil, nil)
//            return LabelToImage.stringToImage("?")
        }

    }
    
}
