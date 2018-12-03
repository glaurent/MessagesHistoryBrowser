//
//  AboutViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 03/12/2018.
//  Copyright © 2018 Guillaume Laurent. All rights reserved.
//

import Cocoa

class AboutViewController: NSViewController {

    @IBOutlet weak var versionNumberTextField: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        if let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {

            versionNumberTextField.stringValue = versionNumber
        }

    }
    
}
