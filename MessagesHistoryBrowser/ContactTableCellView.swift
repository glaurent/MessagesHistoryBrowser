//
//  ContactTableCellView.swift
//  MessagesHistoryBrowser
//
//  Created by Guillaume Laurent on 14/12/2018.
//  Copyright © 2018 Guillaume Laurent. All rights reserved.
//

import Cocoa

class ContactTableCellView: NSTableCellView {

    @IBOutlet weak var contactInitialsLabel: NSTextField!

    var circleLayer:CAShapeLayer!

    override func awakeFromNib() {
        wantsLayer = true
//        layer?.backgroundColor = NSColor.blue.cgColor
        circleLayer = CAShapeLayer()
        layer?.addSublayer(circleLayer)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateCircleLayer()
    }

    func updateCircleLayer() {

//        let squareSize = max(contactInitialsLabel.bounds.size.width, contactInitialsLabel.bounds.size.height)

        // create a circle around the imageView
        //
        let squareSize = max(imageView!.bounds.size.width, imageView!.bounds.size.height)
        let squareBounds = NSRect(origin: CGPoint.zero, size: CGSize(width: squareSize, height: squareSize))

        circleLayer.path = CGPath(ellipseIn: squareBounds, transform: nil)
        circleLayer.position = CGPoint(x:imageView!.frame.origin.x, y:(frame.size.height - squareSize) / 2.0)
        circleLayer.lineWidth = 2.0
        circleLayer.strokeColor = NSColor.secondaryLabelColor.cgColor
        circleLayer.fillColor = CGColor.clear
        circleLayer.zPosition = 10.0
    }

    func showLabel() {
        contactInitialsLabel.isHidden = false
        circleLayer.isHidden = false
        imageView?.isHidden = true
    }

    func showImage() {
        contactInitialsLabel.isHidden = true
        circleLayer.isHidden = true
        imageView?.isHidden = false
    }

}
