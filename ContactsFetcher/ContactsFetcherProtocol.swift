//
//  ContactsFetcherProtocol.swift
//  ContactsFetcher
//
//  Created by Guillaume Laurent on 06/09/2018.
//  Copyright © 2018 Guillaume Laurent. All rights reserved.
//

import Foundation

@objc(ContactsFetcherProtocol) protocol ContactsFetcherProtocol {
    func populate(withPhonePrefix:String)

    func nameAndCNIdentifierFromChatIdentifier(_ chatIdentifier:String, serviceName:String, withReply: @escaping (_ nameIdentifierPair:[NSString], _ contactIsKnown:Bool) -> Void)

    func nameForPhoneNumber(_ phoneNumber:String, withReply: @escaping (_ nameIdentifierPair:[NSString]) -> Void)
    func nameForInstantMessageAddress(_ imAddressToSearch:String, withReply: @escaping (_ nameIdentifierPair:[NSString]) -> Void)
    func nameForEmailAddress(_ emailAddressToSearch:String, withReply: @escaping (_ nameIdentifierPair:[NSString]) -> Void)
    func contactImage(_ contactIdentifier:String, withReply: @escaping (_ imageData:NSData, _ initials:[NSString]) -> Void)
    func countryPhonePrefix(withReply: @escaping (NSString) -> Void)
}
