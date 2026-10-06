//
//  TrafficHistoryStore.swift
//  ClashX
//
//

import Collections
import CocoaLumberjackSwift

// App-level traffic/memory history so the dashboard opens with recent data instead of zeros
@MainActor
final class TrafficHistoryStore {
	static let limit = 30
	// Memory barely changes per second; sample every 20 seconds
	static let memoryLimit = 15
	static let memorySampleInterval: TimeInterval = 20

	// Deques stay at full length; leading zeros stand in for missing history
	private var downValues = Deque<CGFloat>(repeating: 0, count: TrafficHistoryStore.limit)
	private var upValues = Deque<CGFloat>(repeating: 0, count: TrafficHistoryStore.limit)
	private var memoryValues = Deque<Int64>(repeating: 0, count: TrafficHistoryStore.memoryLimit)
	private var hasMemorySample = false
	private var lastMemorySampleDate = Date.distantPast
	private(set) var latestMemory: Int64?
	// Push pairs are averaged into one sample, matching the graph interval
	private var lastTrafficSample: (up: Int, down: Int)?

	var down: [CGFloat] {
		Array(downValues)
	}

	var up: [CGFloat] {
		Array(upValues)
	}

	var memory: [Int64] {
		Array(memoryValues)
	}

	func appendTraffic(up: Int, down: Int) {
		// Pair up pushes; each second push appends the average of the pair
		if let last = lastTrafficSample {
			downValues.removeFirst()
			downValues.append(CGFloat(down + last.down) / 2)
			upValues.removeFirst()
			upValues.append(CGFloat(up + last.up) / 2)
			lastTrafficSample = nil
		} else {
			lastTrafficSample = (up: up, down: down)
		}
	}

	func appendMemory(_ value: Int64) {
		// Without a sample yet, wait for a valid value before filling the array
		guard hasMemorySample || value > 0 else { return }
		latestMemory = value
		let now = Date()
		guard now.timeIntervalSince(lastMemorySampleDate) >= TrafficHistoryStore.memorySampleInterval else { return }
		lastMemorySampleDate = now
		if hasMemorySample {
			memoryValues.removeFirst()
			memoryValues.append(value)
		} else {
			// First valid sample fills the whole history instead of jumping from zero
			hasMemorySample = true
			memoryValues = Deque<Int64>(repeating: value, count: TrafficHistoryStore.memoryLimit)
			Logger.log("memory store first-sample fill: \(value)", level: .debug)
		}
	}

	func reset() {
		downValues = Deque<CGFloat>(repeating: 0, count: TrafficHistoryStore.limit)
		upValues = Deque<CGFloat>(repeating: 0, count: TrafficHistoryStore.limit)
		memoryValues = Deque<Int64>(repeating: 0, count: TrafficHistoryStore.memoryLimit)
		hasMemorySample = false
		lastMemorySampleDate = Date.distantPast
		latestMemory = nil
		lastTrafficSample = nil
	}
}
