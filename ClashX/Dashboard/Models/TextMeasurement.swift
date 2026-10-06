//
//  TextMeasurement.swift
//  ClashX Dashboard
//
// Measure string width from the actual font (for data-driven column widths)
//

import AppKit

enum TextMeasurement {
	static func width(of text: String, font: NSFont) -> CGFloat {
		(text as NSString).size(withAttributes: [.font: font]).width
	}

	static func maxWidth(of texts: [String], font: NSFont) -> CGFloat {
		texts.reduce(0) { max($0, width(of: $1, font: font)) }
	}

	// SF Symbol rendered width (16pt base, scaled by font size)
	static func iconWidth(_ name: String, fontSize: CGFloat) -> CGFloat {
		let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
		guard let image else { return fontSize }
		return image.size.width / 16 * fontSize
	}
}
