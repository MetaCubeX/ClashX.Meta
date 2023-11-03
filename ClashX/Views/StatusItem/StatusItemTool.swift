//
//  StatusItemTool.swift
//  ClashX Pro
//
//  Created by yicheng on 2023/3/1.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit

enum StatusItemTool {
    static let menuImage: NSImage = {
        let customImagePath = (NSHomeDirectory() as NSString).appendingPathComponent("/.config/clash/menuImage.png")
        if let image = NSImage(contentsOfFile: customImagePath) {
            image.isTemplate = true
            return image
        }
        if let imagePath = Bundle.main.path(forResource: "menu_icon@2x", ofType: "png"),
           let image = NSImage(contentsOfFile: imagePath) {
            image.isTemplate = true
            return image
        }
        return NSImage()
    }()

    static let font: NSFont = {
        let fontSize: CGFloat = 9
        let font: NSFont
        if let fontName = UserDefaults.standard.string(forKey: "kStatusMenuFontName"),
           let f = NSFont(name: fontName, size: fontSize) {
            font = f
        } else {
            font = NSFont.menuBarFont(ofSize: fontSize)
        }
        return font
    }()
}
