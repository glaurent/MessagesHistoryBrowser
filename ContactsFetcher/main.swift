//
//  main.swift
//  ContactsFetcher
//
//  Created by Guillaume Laurent on 07/09/2018.
//  Copyright © 2018 Guillaume Laurent. All rights reserved.
//

import Foundation

class ServiceDelegate : NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        NSLog("\(#function)")
        newConnection.exportedInterface =  NSXPCInterface(with: ContactsFetcherProtocol.self)
        let exportedObject = ContactsFetcher()
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}

// Create the listener and run it by resuming:
let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate;
listener.resume()
