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

    let countryPhonePrefix = "+33" // TODO : make this user-settable

    static let sharedInstance = ContactsMap()

    var phoneNumbersMap = [String : CNContact]()

    let contactStore = CNContactStore()

    let contactIMFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey, CNContactInstantMessageAddressesKey])

    let contactEmailFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey, CNContactEmailAddressesKey])

    init() {
        
    }

    func populate(completion : () -> Void)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) { () -> Void in

            let contactFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey, CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey])

            do {

                try self.contactStore.enumerateContactsWithFetchRequest(contactFetchRequest) { (contact, stop) -> Void in
                    let phoneNumbers = contact.phoneNumbers
                    if phoneNumbers.count > 0 {
                        for index in 0..<phoneNumbers.count {
                            let phoneNb = phoneNumbers[index].value as! CNPhoneNumber
                            let canonPhoneNb = self.canonicalizePhoneNumber(phoneNb.stringValue)
                            // NSLog("\(__FUNCTION__) phoneNb : %@", canonPhoneNb)
                            self.phoneNumbersMap[canonPhoneNb] = contact
                        }

                    }
                }
            } catch {
                
            }

            dispatch_sync(dispatch_get_main_queue(), completion)
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

        if let contact = phoneNumbersMap[phoneNumber] as CNContact? {
            return contactName(contact)
        }

        return nil

    }

    func nameForInstantMessageAddress(imAddressToSearch:String) -> String?
    {
        
        var res:String?
        
        do {
            
            try contactStore.enumerateContactsWithFetchRequest(contactIMFetchRequest) { (contact, stop) -> Void in
                
                let imAddresses = contact.instantMessageAddresses
                
                for labeledValue in imAddresses {
                    let imAddress = labeledValue.value as! CNInstantMessageAddress
                    if imAddress.username == imAddressToSearch {
                        res = self.contactName(contact)
                        stop.memory = true
                    }
                }
            }
        } catch {
            
        }

        return res
        
    }

    func nameForEmailAddress(emailAddressToSearch:String) -> String? {

        var res:String?
        
        do {
            
            try contactStore.enumerateContactsWithFetchRequest(contactEmailFetchRequest) { (contact, stop) -> Void in
                
                let emailAddresses = contact.emailAddresses
                
                for labeledValue in emailAddresses {
                    let emailAddress = labeledValue.value as! String
                    if emailAddress == emailAddressToSearch {
                        res = self.contactName(contact)
                        stop.memory = true
                    }
                }
            }
        } catch {
            
        }
        
        return res

    }

    func contactName(contact:CNContact) -> String {
        if contact.nickname != "" {
            return contact.nickname
        }
        
        let firstName = contact.givenName
        let lastName = contact.familyName
        return "\(firstName) \(lastName)"
    }
}
