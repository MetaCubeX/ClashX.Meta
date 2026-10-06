//
//  SpeedUtils.swift
//  ClashX
//
//  Created by yicheng on 2023/7/6.
//  Copyright © 2023 west2online. All rights reserved.
//

import Foundation

/// Unified byte-count formatting for the whole app.
///
/// Conventions:
/// - Live rates and subscription quota: binary units (1024-based).
/// - Cumulative volumes and totals: decimal units (1000-based), matching most panels.
/// - Core memory display intentionally stays on ByteCountFormatter (system convention).
enum ByteFormat {
	enum Base {
		case binary   // 1024
		case decimal  // 1000
	}

	private static let units = ["KB", "MB", "GB", "TB"]

	/// - threeSigFig: display surfaces — 123 / 12.3 / 1.23
	/// - integer: dense/narrow surfaces (status item, table columns) — 123 / 12 / 1
	enum Precision {
		case threeSigFig
		case integer
	}

	static func string(_ bytes: Int64, base: Base, suffix: String = "", precision: Precision = .threeSigFig) -> String {
		let step = Double(base == .binary ? 1024 : 1000)
		guard bytes >= Int64(step) else { return "\(bytes)B" + suffix }
		var value = Double(bytes)
		var unitIndex = -1
		while true {
			let next = value / step
			if unitIndex < units.count - 1, next >= 0.9995 {
				value = next
				unitIndex += 1
				if value < 999.5 { break }
			} else {
				break
			}
		}
		guard unitIndex >= 0 else { return "\(bytes)B" + suffix }
		switch precision {
		case .threeSigFig:
			return number(value) + units[unitIndex] + suffix
		case .integer:
			let rounded = value.rounded()
			// Rounding may cross the unit boundary (e.g. 1023.6KB → 1MB).
			if rounded >= step, unitIndex < units.count - 1 {
				return number(rounded / step) + units[unitIndex + 1] + suffix
			}
			return String(Int64(rounded)) + units[unitIndex] + suffix
		}
	}

	/// Three significant figures with trailing zeros trimmed: 123 / 12.3 / 1.23
	static func number(_ value: Double) -> String {
		if value == 0 { return "0" }
		let exponent = floor(log10(value))
		let scale = pow(10, exponent - 2)
		let rounded = (value / scale).rounded() * scale
		let decimals = max(0, 2 - Int(exponent))
		var text = String(format: "%.\(decimals)f", rounded)
		if text.contains(".") {
			while text.hasSuffix("0") {
				text.removeLast()
			}
			if text.hasSuffix(".") {
				text.removeLast()
			}
		}
		return text
	}

	// MARK: Convention wrappers

	/// Live traffic rate; ports the legacy status-item algorithm verbatim:
	/// KB integer; MB with two decimals below 100 and one decimal at 100+;
	/// GB one decimal. Sub-KB rates render as "0KB/s" (legacy truncation).
	static func rate(_ bytesPerSecond: Int) -> String {
		let kb = bytesPerSecond / 1024
		if kb < 1024 {
			return "\(kb)KB/s"
		}
		let mb = Double(kb) / 1024.0
		if mb >= 100 {
			if mb >= 1000 {
				return scaledRateText(mb / 1024, unitIndex: 2) + "/s"
			}
			return scaledRateText(mb, unitIndex: 1) + "/s"
		}
		return scaledRateText(mb, unitIndex: 1) + "/s"
	}

	/// Dynamic digits for a pre-scaled rate value, shared by rate() and the
	/// traffic-chart axis so every speed surface renders identically.
	static func scaledRateText(_ value: Double, unitIndex: Int) -> String {
		switch unitIndex {
		case 0:
			return String(Int(value)) + units[0]           // KB: integer
		case 1:
			let text = value < 100 ? String(format: "%.2f", value)
				: String(format: "%.1f", value)
			return text + units[1]                          // MB: 2 / 1 decimals
		default:
			return String(format: "%.1f", value) + units[min(unitIndex, units.count - 1)]
		}                                                   // GB/TB: 1 decimal
	}

	/// Subscription quota: byte-identical to the legacy formatter
	/// (`ByteCountFormatter` with `.binary` — "1.2 GB", "977 KB", "512 Bytes").
	static func quota(_ bytes: Int64) -> String {
		Self.quotaFormatter.string(fromByteCount: bytes)
	}

	private static let quotaFormatter: ByteCountFormatter = {
		let formatter = ByteCountFormatter()
		formatter.countStyle = .binary
		return formatter
	}()

	/// Cumulative transfer volumes/totals: decimal units.
	static func total(_ bytes: Int64, precision: Precision = .threeSigFig) -> String {
		string(bytes, base: .decimal, precision: precision)
	}
}

// Menu-bar status item; compact legacy surface over the shared engine.
enum SpeedUtils {
	static func getSpeedString(for byte: Int) -> String {
		ByteFormat.rate(byte)
	}
}
