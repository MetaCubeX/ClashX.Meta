//
//  StatusItemView.swift
//  ClashX
//
//  Created by CYC on 2018/6/23.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import AppKit
import Foundation
import RxCocoa
import RxSwift

class StatusItemView: NSView {
    @IBOutlet var imageView: NSImageView!

    @IBOutlet var uploadSpeedLabel: NSTextField!
    @IBOutlet var downloadSpeedLabel: NSTextField!
    @IBOutlet var speedContainerView: NSView!

    weak var statusItem: NSStatusItem?

    lazy var menuImage: NSImage = {
        let customImagePath = (NSHomeDirectory() as NSString).appendingPathComponent("/.config/clash.meta/menuImage.png")
        if let image = NSImage(contentsOfFile: customImagePath) {
            return image
        }
        if let imagePath = Bundle.main.path(forResource: "menu_icon@2x", ofType: "png"),
           let image = NSImage(contentsOfFile: imagePath) {
            return image
        }
        return NSImage()
    }()

    static func create(statusItem: NSStatusItem?) -> StatusItemView {
        var topLevelObjects: NSArray?
        if Bundle.main.loadNibNamed("StatusItemView", owner: self, topLevelObjects: &topLevelObjects) {
            let view = (topLevelObjects!.first(where: { $0 is NSView }) as? StatusItemView)!
            view.statusItem = statusItem
            view.setupView()
            return view
        }
        return NSView() as! StatusItemView
    }

    func setupView() {
        let fontSize: CGFloat = 9
        let font: NSFont
        if let fontName = UserDefaults.standard.string(forKey: "kStatusMenuFontName"),
            let f = NSFont(name: fontName, size: fontSize) {
            font = f
        } else {
            font = NSFont.menuBarFont(ofSize: fontSize)
        }
        uploadSpeedLabel.font = font
        downloadSpeedLabel.font = font

        uploadSpeedLabel.textColor = NSColor.black
        downloadSpeedLabel.textColor = NSColor.black
    }

    func updateViewStatus(enableProxy: Bool) {
        let selectedColor = NSColor.red
        let unselectedColor: NSColor
        if #available(OSX 10.14, *) {
            unselectedColor = selectedColor.withSystemEffect(.disabled)
        } else {
            unselectedColor = selectedColor.withAlphaComponent(0.5)
        }

        imageView.image = menuImage.tint(color: enableProxy ? selectedColor : unselectedColor)
        updateStatusItemView()
    }
    
    func getSpeedString(for byte: Int) -> String {
        let kb = byte / 1024
        if kb < 1024 {
            return  "\(kb)KB/s"
        } else {
            let mb = Double(kb) / 1024.0
            if mb >= 100 {
                if mb >= 1000 {
                    return String(format: "%.1fGB/s", mb/1024)
                }
                return String(format: "%.1fMB/s", mb)
            } else {
                return String(format: "%.2fMB/s", mb)
            }
        }
    }
    

    func updateSpeedLabel(up: Int, down: Int) {
        guard !speedContainerView.isHidden else { return }
        let finalUpStr = getSpeedString(for: up)
        let finalDownStr = getSpeedString(for: down)

        if downloadSpeedLabel.stringValue == finalDownStr && uploadSpeedLabel.stringValue == finalUpStr {
            return
        }
        downloadSpeedLabel.stringValue = finalDownStr
        uploadSpeedLabel.stringValue = finalUpStr
        updateStatusItemView()
    }

    func showSpeedContainer(show: Bool) {
        speedContainerView.isHidden = !show
        updateStatusItemView()
    }

    func updateStatusItemView() {
        statusItem?.updateImage(withView: self)
    }
}

extension NSStatusItem {
    func updateImage(withView view: NSView) {
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            let img = NSImage(size: view.bounds.size)
            img.addRepresentation(rep)
            img.isTemplate = true
            image = img
        }
    }
}
