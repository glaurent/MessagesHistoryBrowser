//
//  ContactsMapProxy.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 07/09/2018.
//  Copyright © 2018 Guillaume Laurent. All rights reserved.
//

import Cocoa

/**
 * Wraps XPC service to return Swift objects
 */
class ContactsMapProxy {

    static let sharedInstance = ContactsMapProxy()

    var connection:NSXPCConnection

    var contactsFetcher:ContactsFetcherProtocol

    init() {
        connection = NSXPCConnection(serviceName: "org.telegraph-road.MessagesHistoryBrowser.ContactsFetcher")
        connection.remoteObjectInterface = NSXPCInterface(with: ContactsFetcherProtocol.self)
        connection.resume()

//        contactsFetcher = connection.remoteObjectProxy as! ContactsFetcherProtocol
        contactsFetcher = connection.synchronousRemoteObjectProxyWithErrorHandler({ (error) in
            NSLog("XPC proxy error \(error)")
        }) as! ContactsFetcherProtocol

    }

    func populate() {
        contactsFetcher.populate()
    }

    func nameAndCNIdentifierFromChatIdentifier(_ identifier:String, serviceName:String, withReply reply: @escaping (_ nameIdentifierPair:(String, String)?, _ contactIsKnown:Bool) -> Void) {

        contactsFetcher.nameAndCNIdentifierFromChatIdentifier(identifier, serviceName: serviceName) { (nsStrings, contactIsKnown) in

            reply((nsStrings[0] as String, nsStrings[1] as String), contactIsKnown)

        }
    }

    func nameForPhoneNumber(_ phoneNumber:String, reply: @escaping ((String, String)?) -> Void)  {
        contactsFetcher.nameForPhoneNumber(phoneNumber) { nsStrings in

            if nsStrings[0].length == 0 {
                reply(nil)
            } else {
                reply((nsStrings[0] as String, nsStrings[1] as String))
            }
        }
    }

    func nameForInstantMessageAddress(_ imAddressToSearch:String, reply: @escaping ((String, String)?) -> Void) {
        contactsFetcher.nameForInstantMessageAddress(imAddressToSearch) { nsStrings in

            if nsStrings[0].length == 0 {
                reply(nil)
            } else {
                reply((nsStrings[0] as String, nsStrings[1] as String))
            }

        }
    }

    func nameForEmailAddress(_ emailAddressToSearch:String, reply: @escaping ((String, String)?) -> Void) {
        contactsFetcher.nameForEmailAddress(emailAddressToSearch) { nsStrings in

            if nsStrings[0].length == 0 {
                reply(nil)
            } else {
                reply((nsStrings[0] as String, nsStrings[1] as String))
            }

        }
    }

    // returns the contact's image or its initials (firstname, lastname)
    //
    func contactImage(_ contactIdentifier:String, reply: @escaping (NSImage?, (String, String)?) -> Void) {
        contactsFetcher.contactImage(contactIdentifier) { (data, initials) in

            if data.length > 0 {
                reply(NSImage(data: data as Data), nil)
            } else if initials.count == 2 {
                reply(nil, (initials[0] as String, initials[1] as String))
            } else {
                reply(nil, nil)
            }

        }

    }

    func countryPhonePrefix(reply: @escaping (String) -> Void) {
        contactsFetcher.countryPhonePrefix() { (prefix:NSString) in
            reply(prefix as String)
        }
    }

}
