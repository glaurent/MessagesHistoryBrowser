//
//  ContactsPhoneNumberList.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 26/09/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import Contacts

class ContactsMap : NSObject {

//    let countryPhonePrefix = "+33"
    var countryPhonePrefix:String

    static let sharedInstance = ContactsMap()

    var phoneNumbersMap = [String : CNContact]()

    let contactStore = CNContactStore()

    let contactIMFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey, CNContactInstantMessageAddressesKey])

    let contactEmailFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey, CNContactEmailAddressesKey])

    var progress:NSProgress?

    override init()
    {
        countryPhonePrefix = "+1" // default to US prefix

        if let val = NSUserDefaults.standardUserDefaults().valueForKey("CountryPhonePrefix") {

            if let valNum = val as? NSNumber {
                countryPhonePrefix = "+" + valNum.stringValue
            } else if let valString = val as? String {
                countryPhonePrefix = "+" + valString
            }

            print("Found default value for CountryPhonePrefix : \(val)")
            
        } else if let jsonCountryPhoneCodeFileURL = NSBundle.mainBundle().URLForResource("phone country codes", withExtension: "json"),
            jsonData = NSData(contentsOfURL: jsonCountryPhoneCodeFileURL) {

                do {
                    var countryPhonePrefixDict:[String:String]

                    try countryPhonePrefixDict = NSJSONSerialization.JSONObjectWithData(jsonData, options: NSJSONReadingOptions(rawValue:0)) as! [String : String]

                    if let countryCode = NSLocale.currentLocale().objectForKey(NSLocaleCountryCode) as? String,
                    phonePrefix = countryPhonePrefixDict[countryCode] {

                        if phonePrefix.characters.first == "+" {
                            countryPhonePrefix = phonePrefix
                        } else {
                            countryPhonePrefix = "+" + phonePrefix
                        }
                        NSUserDefaults.standardUserDefaults().setValue(phonePrefix, forKey: "CountryPhonePrefix")
                    }

                } catch {
                    print("Couldn't parse JSON phone code data")
                }
        }

        super.init()
        
    }

    func populate()
    {

        // get number of contacts so we can set the totalUnitCount of this NSProgress
        //
        let predicate = CNContact.predicateForContactsInContainerWithIdentifier(contactStore.defaultContainerIdentifier())
        if let allContactsForCount = try? contactStore.unifiedContactsMatchingPredicate(predicate, keysToFetch: [CNContactGivenNameKey]) {
            progress = NSProgress(totalUnitCount: Int64(allContactsForCount.count))
        }

        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) { () -> Void in

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
                            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                self.progress?.completedUnitCount = Int64(index)
                            })
                            
                        }
                        
                    }
                }
            } catch {
                
            }
        }

        self.progress = nil

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

    func nameForPhoneNumber(phoneNumber:String) -> (String, String)? {

        if let contact = phoneNumbersMap[phoneNumber] as CNContact? {
            return (contactName(contact), contact.identifier)
        }

        return nil

    }

    func nameForInstantMessageAddress(imAddressToSearch:String) -> (String, String)?
    {
        
        var res:(String, String)?
        
        do {
            
            try contactStore.enumerateContactsWithFetchRequest(contactIMFetchRequest) { (contact, stop) -> Void in
                
                let imAddresses = contact.instantMessageAddresses
                
                for labeledValue in imAddresses {
                    let imAddress = labeledValue.value as! CNInstantMessageAddress
                    if imAddress.username == imAddressToSearch {
                        res = (self.contactName(contact), contact.identifier)
                        stop.memory = true
                    }
                }
            }
        } catch {
            
        }

        return res
        
    }

    func nameForEmailAddress(emailAddressToSearch:String) -> (String, String)? {

        var res:(String, String)?
        
        do {
            
            try contactStore.enumerateContactsWithFetchRequest(contactEmailFetchRequest) { (contact, stop) -> Void in
                
                let emailAddresses = contact.emailAddresses
                
                for labeledValue in emailAddresses {
                    let emailAddress = labeledValue.value as! String
                    if emailAddress == emailAddressToSearch {
                        res = (self.contactName(contact), contact.identifier)
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

    func contactImage(contactIdentifier:String) -> NSImage? {
        do {
            let contact = try contactStore.unifiedContactWithIdentifier(contactIdentifier, keysToFetch:[CNContactImageDataKey, CNContactThumbnailImageDataKey, CNContactGivenNameKey, CNContactFamilyNameKey])
            if let imageData = contact.imageData {
                return NSImage(data: imageData) // thumbnailImageData is nil, why ?
            } else { // get a bitmap of the contact's initials (like in Contacts.app)
                let firstName = contact.givenName
                let lastName = contact.familyName

                var initials = ""

                if firstName.characters.count > 0 {
                    initials = initials + "\(firstName.characters.first!)"
                }
                if lastName.characters.count > 0 {
                    initials = initials + "\(lastName.characters.first!)"
                }

                if let imageLabel = LabelToImage.stringToImage(initials) {
                    return imageLabel
                }
            }
        } catch {
            NSLog("Couldn't get contact \(contactIdentifier)")
        }

        return nil
    }
    
}
