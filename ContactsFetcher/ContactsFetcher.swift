//
//  ContactsFetcher.swift
//  ContactsFetcher
//
//  Created by Guillaume Laurent on 07/09/2018.
//  Copyright © 2018 Guillaume Laurent. All rights reserved.
//

import Cocoa

class ContactsFetcher: NSObject, ContactsFetcherProtocol {

    let contactsMap = ContactsMap.sharedInstance

    let emptyResult = [NSString(), NSString()]

    override init() {
//        contactsMap.populate()
    }

    func populate(withPhonePrefix phonePrefix:String) {
        contactsMap.populate(withCountryPhonePrefix: phonePrefix)
    }

    func nameAndCNIdentifierFromChatIdentifier(_ identifier:String, serviceName:String, withReply reply: @escaping (_ nameAndCNIdentifierPair:[NSString], _ contactIsKnown:Bool) -> Void) {

        var contactName = ""
        var contactCNIdentifier = ""
        var contactIsKnown = false

        if serviceName == "AIM" || serviceName == "Jabber" {

            if let nameCNIdentifierPair = contactsMap.nameForInstantMessageAddress(identifier) {

                contactIsKnown = true
                contactName = nameCNIdentifierPair.0
                contactCNIdentifier = nameCNIdentifierPair.1

            } else {
                contactIsKnown = false
                NSLog("\(#function) : no contact name found for identifier \(identifier)")
            }

        } else if serviceName == "iMessage" || serviceName == "SMS" {

            // check if identifier is an email adress or a phone number
            //
            if identifier.contains("@") {

                if let chatContactNameIdentifierPair = contactsMap.nameForEmailAddress(identifier) {

                    contactName = chatContactNameIdentifierPair.0
                    contactCNIdentifier = chatContactNameIdentifierPair.1
                    contactIsKnown = true

                }

            } else {

                if let chatContactNameIdentifierPair = contactsMap.nameForPhoneNumber(identifier) {
                    contactName = chatContactNameIdentifierPair.0
                    contactCNIdentifier = chatContactNameIdentifierPair.1
                    contactIsKnown = true
                } else {
                    contactName = identifier
                    contactIsKnown = false
                }
            }

        } else { // other kind of serviceName - shouldn't happen now that Messages only supports iMessages and no other IM protocols
            contactName = identifier
            contactIsKnown = false
        }

//        NSLog("\(#function) calling reply for \(identifier) : \(contactName) - known \(contactIsKnown)")
        reply([contactName as NSString, contactCNIdentifier as NSString], contactIsKnown)
    }

    func nameForPhoneNumber(_ phoneNumber:String, withReply reply: ([NSString]) -> Void) {
        if let res = contactsMap.nameForPhoneNumber(phoneNumber) {
            reply([res.0 as NSString, res.1 as NSString])
        } else {
            reply(emptyResult)
        }
    }

    func nameForInstantMessageAddress(_ imAddressToSearch:String, withReply reply: ([NSString]) -> Void) {
        if let res = contactsMap.nameForInstantMessageAddress(imAddressToSearch) {
            reply([res.0 as NSString, res.1 as NSString])
        } else {
            reply(emptyResult)
        }
    }

    func nameForEmailAddress(_ emailAddressToSearch:String, withReply reply: ([NSString]) -> Void) {
        if let res = contactsMap.nameForEmailAddress(emailAddressToSearch) {
            reply([res.0 as NSString, res.1 as NSString])
        } else {
            reply(emptyResult)
        }
    }

    func contactImage(_ contactIdentifier:String, withReply reply: (NSData, [NSString]) -> Void) {
        let (image, initials) = contactsMap.contactImage(contactIdentifier)
        if let image = image {
            if let res = image.tiffRepresentation as NSData? {
                reply(res, [])
                return
            }
        }

        if let initials = initials {
            reply(NSData(), [initials.0 as NSString, initials.1 as NSString])
        } else {
            reply(NSData(), [])
        }

    }

    func countryPhonePrefix(withReply reply: (NSString) -> Void) {
        reply(contactsMap.countryPhonePrefix as NSString)
    }

}
