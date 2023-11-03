//
//  NormalMenuItemView.swift
//  ClashX
//
//  Created by yicheng on 2023/6/25.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit

@available(macOS 11.0, *)
class NormalMenuItemView: MenuItemBaseView {
    let label: NSTextField
    private let arrowLabel: NSControl = {
        let image = NSImage(named: NSImage.goForwardTemplateName)!.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold, scale: .small))!
        return NSImageView(image: image)
    }()

    init(_ title: String, rightArrow: Bool) {
        label = NSTextField(labelWithString: title)
        label.font = type(of: self).labelFont
        label.sizeToFit()
        let rect = NSRect(x: 0, y: 0, width: label.bounds.width + 40 + arrowLabel.bounds.width, height: 20)
        super.init(frame: rect, autolayout: false)
        addSubview(label)
        label.frame = NSRect(x: 20, y: 0, width: label.bounds.width, height: 20)
        label.textColor = NSColor.labelColor
        if rightArrow {
            addSubview(arrowLabel)
        }
    }

    override func layoutSubtreeIfNeeded() {
        super.layoutSubtreeIfNeeded()
        arrowLabel.frame = NSRect(x: bounds.width - arrowLabel.bounds.width - 12, y: 0, width: arrowLabel.bounds.width, height: 20)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var cells: [NSCell?] {
        return [label.cell, arrowLabel.cell]
    }

    override var labels: [NSTextField] {
        return [label]
    }
}

@available(macOS 11.0, *)
extension NormalMenuItemView: ProxyGroupMenuHighlightDelegate {
    func highlight(item: NSMenuItem?) {
        if enclosingMenuItem?.hasSubmenu == true, let item = item {
            if enclosingMenuItem?.submenu?.items.contains(item) == true {
                isHighlighted = true
                return
            }
        }
        isHighlighted = item == enclosingMenuItem
    }
}
