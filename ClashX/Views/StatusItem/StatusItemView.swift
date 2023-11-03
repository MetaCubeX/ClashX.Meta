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

class StatusItemView: NSView, StatusItemViewProtocol {
    @IBOutlet var imageView: NSImageView!

    @IBOutlet var uploadSpeedLabel: NSTextField!
    @IBOutlet var downloadSpeedLabel: NSTextField!
    @IBOutlet var speedContainerView: NSView!

    var up: Int = 0
    var down: Int = 0

    static func create(statusItem: NSStatusItem?) -> StatusItemView {
        var topLevelObjects: NSArray?
        if Bundle.main.loadNibNamed("StatusItemView", owner: self, topLevelObjects: &topLevelObjects) {
            let view = (topLevelObjects!.first(where: { $0 is NSView }) as? StatusItemView)!
            view.setupView()
            view.imageView.image = StatusItemTool.menuImage

            if let button = statusItem?.button {
                button.addSubview(view)
                button.imagePosition = .imageOverlaps
            } else {
                Logger.log("button = nil")
                AppDelegate.shared.openConfigFolder(self)
            }
            view.updateViewStatus(enableProxy: false)
            return view
        }
        return NSView() as! StatusItemView
    }

    func setupView() {
        uploadSpeedLabel.font = StatusItemTool.font
        downloadSpeedLabel.font = StatusItemTool.font

        uploadSpeedLabel.textColor = NSColor.labelColor
        downloadSpeedLabel.textColor = NSColor.labelColor
    }

    func updateSize(width: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: width, height: 22)
    }

    func updateViewStatus(enableProxy: Bool) {
        if enableProxy {
            imageView.contentTintColor = NSColor.labelColor
        } else {
            imageView.contentTintColor = NSColor.labelColor.withSystemEffect(.disabled)
        }
    }

    func updateSpeedLabel(up: Int, down: Int) {
        guard !speedContainerView.isHidden else { return }
        if up != self.up {
            uploadSpeedLabel.stringValue = SpeedUtils.getSpeedString(for: up)
            self.up = up
        }
        if down != self.down {
            downloadSpeedLabel.stringValue = SpeedUtils.getSpeedString(for: down)
            self.down = down
        }
    }

    func showSpeedContainer(show: Bool) {
        speedContainerView.isHidden = !show
    }
}
