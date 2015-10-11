//
//  MessagesListViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 04/10/15.
//  Copyright © 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class MessagesListViewController: NSViewController {

    @IBOutlet weak var messagesTextView: NSTextView!
    
    @IBOutlet weak var attachmentsCollectionView: NSCollectionView!


    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
}
