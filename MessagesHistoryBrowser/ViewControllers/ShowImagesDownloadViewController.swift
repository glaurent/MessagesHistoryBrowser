//
//  ShowImagesDownloadViewController.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 05/09/2018.
//  Copyright © 2018 Guillaume Laurent. All rights reserved.
//

import Cocoa

class ShowImagesDownloadViewController: NSViewController {

    static let ShowImagesDownloadUserDefaultsKey = "ShowImagesDownloadUserDefaultsKey"

    @IBOutlet weak var dontShowAgainCheckBox: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    @IBAction func okButtonClicked(_ sender: Any) {
        
        if dontShowAgainCheckBox.state == .on {
            UserDefaults.standard.set(true, forKey: ShowImagesDownloadViewController.ShowImagesDownloadUserDefaultsKey)
        }

        view.window?.sheetParent?.endSheet(view.window!)
    }
}
