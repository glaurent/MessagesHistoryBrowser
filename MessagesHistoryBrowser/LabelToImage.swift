//
//  LabelToImage.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 23/01/16.
//  Copyright © 2016 Guillaume Laurent. All rights reserved.
//

import Cocoa

class LabelToImage
{
    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))

    static let sharedInstance = LabelToImage()

    init()
    {
        view.wantsLayer = true
        view.addSubview(textField)

        view.layer?.backgroundColor = NSColor.lightGray.cgColor

        textField.frame.origin = NSPoint(x:0, y:-13)
        textField.drawsBackground = true
        textField.alignment = .center
        textField.isBezeled = false
        textField.font = NSFont.systemFont(ofSize: 20.0)
        textField.backgroundColor = NSColor.lightGray
        textField.textColor = NSColor.white
    }

    func stringToImage(_ label:String) -> NSImage?
    {

        textField.stringValue = label

        if let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.frame) {

            view.cacheDisplay(in: view.frame, to: bitmapRep)

            if let cgiImage = bitmapRep.cgImage {
                return NSImage(cgImage: cgiImage, size: view.frame.size)
            } else {
                print("stringToImage : bitmapRep has no CGIImage")
            }

        } else {
            print("stringToImage : no bitmapRep")
        }

        return nil

    }

    class func stringToImage(_ label:String) -> NSImage?
    {
        return LabelToImage.sharedInstance.stringToImage(label)
    }

}
