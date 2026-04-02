//
//  CustomTextLabel.swift
//  ClashX
//
//  Created to fix high CPU usage issue on macOS 26.1+
//  Replaces NSTextField with custom drawing to avoid infinite draw loop
//

import AppKit
import Foundation

class CustomTextLabel: NSView {
    var text: String = "" {
        didSet {
            if text != oldValue {
                needsDisplay = true
            }
        }
    }
    
    var font: NSFont = NSFont.systemFont(ofSize: 8) {
        didSet {
            needsDisplay = true
        }
    }
    
    var textColor: NSColor = NSColor.labelColor {
        didSet {
            needsDisplay = true
        }
    }
    
    var alignment: NSTextAlignment = .right {
        didSet {
            needsDisplay = true
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard !text.isEmpty else { return }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let size = attributedString.size()
        
        // Calculate position based on alignment
        let rect: NSRect
        switch alignment {
        case .right:
            rect = NSRect(
                x: bounds.width - size.width,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        case .left:
            rect = NSRect(
                x: 0,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        case .center:
            rect = NSRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        default:
            rect = NSRect(
                x: 0,
                y: (bounds.height - size.height) / 2,
                width: bounds.width,
                height: size.height
            )
        }
        
        attributedString.draw(in: rect)
    }
}

