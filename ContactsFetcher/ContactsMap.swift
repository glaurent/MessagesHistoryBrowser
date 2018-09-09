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

    let contactIMFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactFamilyNameKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor, CNContactInstantMessageAddressesKey as CNKeyDescriptor])

    let contactEmailFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactFamilyNameKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor])

    var progress:Progress?

    override init()
    {
        countryPhonePrefix = "+1" // default to US prefix

        if let val = UserDefaults.standard.value(forKey: "CountryPhonePrefix") {

            if let valNum = val as? NSNumber {
                countryPhonePrefix = "+" + valNum.stringValue
            } else if let valString = val as? String {
                countryPhonePrefix = "+" + valString
            }

            print("Found default value for CountryPhonePrefix : \(val)")
            
        } else if let jsonCountryPhoneCodeFileURL = Bundle.main.url(forResource: "phone country codes", withExtension: "json"),
            let jsonData = try? Data(contentsOf: jsonCountryPhoneCodeFileURL) {

                do {
                    var countryPhonePrefixDict:[String:String]

                    try countryPhonePrefixDict = JSONSerialization.jsonObject(with: jsonData, options: JSONSerialization.ReadingOptions(rawValue:0)) as! [String : String]

                    if let countryCode = (Locale.current as NSLocale).object(forKey: NSLocale.Key.countryCode) as? String,
                    let phonePrefix = countryPhonePrefixDict[countryCode] {

                        if phonePrefix.first == "+" {
                            countryPhonePrefix = phonePrefix
                        } else {
                            countryPhonePrefix = "+" + phonePrefix
                        }
                        UserDefaults.standard.setValue(phonePrefix, forKey: "CountryPhonePrefix")
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
        let predicate = CNContact.predicateForContactsInContainer(withIdentifier: contactStore.defaultContainerIdentifier())
        if let allContactsForCount = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor]) {
            progress = Progress(totalUnitCount: Int64(allContactsForCount.count))
//            NSLog("\(#function) : nb of contacts : \(allContactsForCount.count)")
        }

        DispatchQueue.global(qos: .background).sync { () -> Void in

            let contactFetchRequest = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor])

            do {

                try self.contactStore.enumerateContacts(with: contactFetchRequest) { (contact, stop) -> Void in
//                    NSLog("contact : \(contact.givenName)")

                    let phoneNumbers = contact.phoneNumbers
                    if phoneNumbers.count > 0 {
                        for index in 0..<phoneNumbers.count {
                            let phoneNb = phoneNumbers[index].value 
                            let canonPhoneNb = self.canonicalizePhoneNumber(phoneNb.stringValue)
                            // NSLog("\(#function) phoneNb : %@", canonPhoneNb)
                            self.phoneNumbersMap[canonPhoneNb] = contact
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

        if res.hasPrefix("0") {
            let skip0Index = res.index(res.startIndex, offsetBy: 1)
//            res = countryPhonePrefix + res.substring(from: skip0Index)
            res = countryPhonePrefix + res[skip0Index...]
        }

        return res
    }

    func nameForPhoneNumber(_ phoneNumber:String) -> (String, String)? {

        if let contact = phoneNumbersMap[phoneNumber] as CNContact? {
            return (contactName(contact), contact.identifier)
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
                        res = (self.contactName(contact), contact.identifier)
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
                        res = (self.contactName(contact), contact.identifier)
                        stop.pointee = true
                    }
                }
            }
        } catch {
            
        }
        
        return res

    }

    private func contactName(_ contact:CNContact) -> String {
        if contact.nickname != "" {
            return contact.nickname
        }
        
        let firstName = contact.givenName
        let lastName = contact.familyName
        return "\(firstName) \(lastName)"
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
