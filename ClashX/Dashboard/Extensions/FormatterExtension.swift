//
//  FormatterExtension.swift
//  ClashX Dashboard
//
//

import Foundation

enum DashboardFormatters {
	static let relativeDateTimeShort: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .short
		return formatter
	}()

	static let relativeDateTimeAbbreviated: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .abbreviated
		return formatter
	}()

	static func providerUpdateText(for date: Date) -> String {
		let relative = Self.relativeDateTimeAbbreviated.localizedString(for: date, relativeTo: Date())
		return String(format: NSLocalizedString("Updated %@", comment: ""), relative)
	}
}
