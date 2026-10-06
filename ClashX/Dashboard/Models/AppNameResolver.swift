//
//  AppNameResolver.swift
//  ClashX Dashboard
//

import Foundation
import AppKit
import CryptoKit

actor AppNameResolver {
	static let iconSize = NSSize(width: 21, height: 21)

	private var appNameCache: [String: String] = [:]         // processPath → appName
	private var iconByNameCache: [String: NSImage] = [:]    // appName → icon
	private var noIconSet: Set<String> = []

	func appName(processPath: String, process: String) -> String {
		if let hit = appNameCache[processPath] { return hit }
		let name = resolveAppName(processPath: processPath, process: process)
		appNameCache[processPath] = name
		return name
	}

	func allAppNames(for conns: [DBConnection]) -> [String] {
		var set = Set<String>()
		for conn in conns {
			set.insert(appName(processPath: conn.metadata.processPath, process: conn.metadata.process))
		}
		var sorted = set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
		if let idx = sorted.firstIndex(of: "Unknown") {
			let unknown = sorted.remove(at: idx)
			sorted.append(unknown)
		}
		return sorted
	}

	func buildNameMap(for conns: [DBConnection]) -> [String: String] {
		var map: [String: String] = [:]
		for conn in conns {
			let path = conn.metadata.processPath
			if map[path] == nil {
				map[path] = appName(processPath: path, process: conn.metadata.process)
			}
		}
		return map
	}

	func appIcon(processPath: String, process: String) async -> NSImage? {
		let name = appName(processPath: processPath, process: process)
		if let hit = iconByNameCache[name] { return hit }
		let key = iconCacheKey(for: processPath)
		if let disk = AppIconDiskCache.load(for: key) {
			iconByNameCache[name] = disk
			return disk
		}
		return await loadAndCacheIcon(for: processPath)
	}

	private func loadAndCacheIcon(for processPath: String) async -> NSImage? {
		let key = iconCacheKey(for: processPath)
		if let path = bundlePath(for: processPath) {
			let icon = NSWorkspace.shared.icon(forFile: path)
			icon.size = Self.iconSize
			let name = appNameCache[processPath] ?? "Unknown"
			iconByNameCache[name] = icon
			Task.detached(priority: .utility) { AppIconDiskCache.save(icon, for: key) }
			return icon
		}
		noIconSet.insert(key)
		return nil
	}

	// MARK: - Helpers

	private func bundlePath(for processPath: String) -> String? {
		var dir = ""
		for part in processPath.split(separator: "/") {
			dir += "/" + part
			if part.hasSuffix(".app"), FileManager.default.fileExists(atPath: dir) {
				return dir
			}
		}
		if !processPath.isEmpty, FileManager.default.fileExists(atPath: processPath) {
			return processPath
		}
		return nil
	}

	private func iconCacheKey(for processPath: String) -> String {
		let bundle = bundlePath(for: processPath) ?? processPath
		let mtime: TimeInterval
		if let attrs = try? FileManager.default.attributesOfItem(atPath: bundle),
		   let date = attrs[.modificationDate] as? Date {
			mtime = date.timeIntervalSince1970
		} else {
			mtime = 0
		}
		return "\(bundle)-\(mtime)"
	}

	private func resolveAppName(processPath: String, process: String) -> String {
		var dir = ""
		for part in processPath.split(separator: "/") {
			dir += "/" + part
			if part.hasSuffix(".app"), FileManager.default.fileExists(atPath: dir) {
				return String(part.dropLast(4))
			}
		}
		return process.isEmpty ? "Unknown" : process
	}
}

// MARK: - Disk Cache

enum AppIconDiskCache {
	private static var cacheURL: URL {
		let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
		return base.appendingPathComponent("ClashX/AppIcons", isDirectory: true)
	}

	private static func fileURL(for key: String) -> URL {
		let hash = SHA256.hash(data: Data(key.utf8))
		let name = hash.compactMap { String(format: "%02x", $0) }.joined()
		return cacheURL.appendingPathComponent(name + ".png")
	}

	static func load(for key: String) -> NSImage? {
		let url = fileURL(for: key)
		guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
		image.size = AppNameResolver.iconSize
		return image
	}

	static func save(_ image: NSImage, for key: String) {
		try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
		guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
		let url = fileURL(for: key)
		try? png.write(to: url, options: .atomic)
	}
}
