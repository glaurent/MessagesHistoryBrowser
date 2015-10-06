//
//  ContactsPhoneNumberList.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 26/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import AddressBook

class ContactsMap {

    let countryPhonePrefix = "+33" // TODO : make this user-settable

    static let sharedInstance = ContactsMap()

    var phoneNumbersMap = [String : ABPerson]()

    let addressBook = ABAddressBook.sharedAddressBook()

    init() {

        let allContacts = addressBook.people() as! [ABPerson]

        for person in allContacts {
            let tmp = person.valueForProperty(kABPhoneProperty)

            if let phoneNumbers = tmp as? ABMultiValue {

                for index in 0..<phoneNumbers.count() {
                    let phoneNb = phoneNumbers.valueAtIndex(index) as! String
                    let canonPhoneNb = canonicalizePhoneNumber(phoneNb)
                    NSLog("\(__FUNCTION__) phoneNb : %@", canonPhoneNb)
                    phoneNumbersMap[canonPhoneNb] = person
                }
            }
        }
    }

    func canonicalizePhoneNumber(rawPhoneNumber:String) -> String {

        var res = ""

        for ch in rawPhoneNumber.characters {
            switch ch {
            case "0"..."9", "+":
                res.append(ch)

            default:
                break // skip character
            }
        }

        if res.hasPrefix("0") {
            let skip0Index = res.startIndex.advancedBy(1)
            res = countryPhonePrefix + res.substringFromIndex(skip0Index)
        }

        return res
    }

    func nameForPhoneNumber(phoneNumber:String) -> String? {
        
        if let contact = phoneNumbersMap[phoneNumber] as ABPerson? {
            return contactName(contact)
        }

        return nil

    }

    func nameForInstantMessageAddress(imAddress:String) -> String? {
        let chatIdentifierSearchElement = ABPerson.searchElementForProperty(kABInstantMessageProperty, label: nil, key: nil, value: imAddress,
            comparison:ABSearchComparison(kABEqualCaseInsensitive.rawValue))

        let tmpContacts = addressBook.recordsMatchingSearchElement(chatIdentifierSearchElement)


        if tmpContacts.count > 0 {
            let chatContact = tmpContacts[0] as! ABPerson
            return contactName(chatContact)
        }

        return nil
    }

    func nameForEmailAddress(emailAddress:String) -> String? {

        let chatIdentifierSearchElement = ABPerson.searchElementForProperty(kABEmailProperty, label: nil, key: nil, value: emailAddress,
            comparison:ABSearchComparison(kABEqualCaseInsensitive.rawValue))

        let tmpContacts = addressBook.recordsMatchingSearchElement(chatIdentifierSearchElement)


        if tmpContacts.count > 0 {
            let chatContact = tmpContacts[0] as! ABPerson
            return contactName(chatContact)
        }

        return nil
    }

    func contactName(contact:ABPerson) -> String {
        let firstName = contact.valueForProperty(kABFirstNameProperty) as? String ?? ""
        let lastName = contact.valueForProperty(kABLastNameProperty) as? String ?? ""
        return "\(firstName) \(lastName)"
    }
}
