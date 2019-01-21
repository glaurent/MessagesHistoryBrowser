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

    var phoneNumbersMap = [String : String]() // maps contact phone numbers (as found in Messages.app chats) to contact identifiers (as used by the Contacts framework)

    let contactStore = CNContactStore()

    let contactIMFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey, CNContactInstantMessageAddressesKey] as [CNKeyDescriptor])

    let contactEmailFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey, CNContactEmailAddressesKey] as [CNKeyDescriptor])

    var progress:Progress?

    let contactFormatter = CNContactFormatter()

    init() {
        countryPhonePrefix = "+1"
        contactFormatter.style = .fullName
    }

    func populate(withCountryPhonePrefix phonePrefix:String) -> Bool {

        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return false
        }

        // ensure countryPhonePrefix has a leading "+"
        //
        if phonePrefix.first != "+" {
            countryPhonePrefix = "+" + phonePrefix
        } else {
            countryPhonePrefix = phonePrefix
        }

        // get number of contacts so we can set the totalUnitCount of this NSProgress
        //
        let predicate = CNContact.predicateForContactsInContainer(withIdentifier: contactStore.defaultContainerIdentifier())
        if let allContactsForCount = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor]) {
            progress = Progress(totalUnitCount: Int64(allContactsForCount.count))
//            NSLog("\(#function) : nb of contacts : \(allContactsForCount.count)")
        }

        DispatchQueue.global(qos: .background).sync { () -> Void in

            let keysToFetch = [CNContactPhoneNumbersKey, CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey] as [CNKeyDescriptor]
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: keysToFetch)

            do {

                try self.contactStore.enumerateContacts(with: contactFetchRequest) { (contact, stop) -> Void in
                    NSLog("\(#function) contact : \(contact.givenName)")

                    let phoneNumbers = contact.phoneNumbers
                    if phoneNumbers.count > 0 {
                        for index in 0..<phoneNumbers.count {
                            let phoneNb = phoneNumbers[index].value 
                            let canonPhoneNb = self.canonicalizePhoneNumber(phoneNb.stringValue)
                            NSLog("\(#function) phoneNb : \(canonPhoneNb) for contact \(contact.givenName)")
                            self.phoneNumbersMap[canonPhoneNb] = contact.identifier
                            DispatchQueue.main.async {
                                self.progress?.completedUnitCount = Int64(index)
                            }
                            
                        }
                        
                    }
                }
            } catch let e {
                NSLog("\(#function) error while enumerating contacts : \(e)")
            }

        }

        self.progress = nil

        return true
    }

    func canonicalizePhoneNumber(_ rawPhoneNumber:String) -> String {

        var res = ""

        for ch in rawPhoneNumber {
            switch ch {
            case "0"..."9", "+":
                res.append(ch)

            default:
                break // skip character
            }
        }

        // This really works for French numbers only
        //
        if res.hasPrefix("0") {
            let skip0Index = res.index(res.startIndex, offsetBy: 1)
//            res = countryPhonePrefix + res.substring(from: skip0Index)
            res = countryPhonePrefix + res[skip0Index...]
        }

        return res
    }

    func nameForPhoneNumber(_ phoneNumber:String) -> (String, String)? {

        if let contactIdentifier = phoneNumbersMap[phoneNumber] {

            let contactName = formattedContactName(contactIdentifier) ?? "<unknown> \(phoneNumber)"

            return (contactName, contactIdentifier)

//            return (contactName(contactIdentifier), contact.identifier)
        }

        return nil

    }

    func nameForInstantMessageAddress(_ imAddressToSearch:String) -> (String, String)?
    {
        
        var res:(String, String)?
        
        do {
            
            try contactStore.enumerateContacts(with: contactIMFetchRequest) { (contact, stop) -> Void in
                
                let imAddresses = contact.instantMessageAddresses
                
                for labeledValue in imAddresses {
                    let imAddress = labeledValue.value 
                    if imAddress.username == imAddressToSearch {
                        res = (self.formattedContactName(contact.identifier) ?? imAddressToSearch, contact.identifier)
                        stop.pointee = true
                    }
                }
            }
        } catch {
            
        }

        return res
        
    }

    func nameForEmailAddress(_ emailAddressToSearch:String) -> (String, String)? {

        var res:(String, String)?
        
        do {
            
            try contactStore.enumerateContacts(with: contactEmailFetchRequest) { (contact, stop) -> Void in
                
                let emailAddresses = contact.emailAddresses
                
                for labeledValue in emailAddresses {
                    let emailAddress = labeledValue.value as String
                    if emailAddress == emailAddressToSearch {
                        res = (self.formattedContactName(contact.identifier) ?? emailAddressToSearch, contact.identifier)
                        stop.pointee = true
                    }
                }
            }
        } catch {

        }
        
        return res

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
            if let imageData = contact.imageData {
                return (NSImage(data: imageData), nil) // thumbnailImageData is nil, why ?
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
