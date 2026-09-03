//
//  ProxyConfigHelperXPCTransport.swift
//  ClashX
//

import Foundation

enum ProxyConfigHelperXPCError: LocalizedError, Sendable {
	case invalidRequestEnvelope
	case invalidResponseEnvelope
	case unexpectedMessage(String)
	case unexpectedResponse(expected: String, actual: String)
	case remote(String)
	case propertyListEncodingFailed
	case propertyListDecodingFailed

	var errorDescription: String? {
		switch self {
		case .invalidRequestEnvelope:
			return "Invalid helper request envelope."
		case .invalidResponseEnvelope:
			return "Invalid helper response envelope."
		case let .unexpectedMessage(kind):
			return "Unexpected helper message: \(kind)."
		case let .unexpectedResponse(expected, actual):
			return "Unexpected helper response. expected=\(expected) actual=\(actual)."
		case let .remote(message):
			return message
		case .propertyListEncodingFailed:
			return "Failed to encode property list payload."
		case .propertyListDecodingFailed:
			return "Failed to decode property list payload."
		}
	}
}

struct ProxyConfigHelperExplicitSuccess: Codable, Sendable {}

struct ProxyConfigHelperPropertyList: Codable, Sendable {
	let data: Data

	init(_ dictionary: [String: Any]) throws {
		guard PropertyListSerialization.propertyList(dictionary, isValidFor: .binary) else {
			throw ProxyConfigHelperXPCError.propertyListEncodingFailed
		}
		self.data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
	}

	func dictionary() throws -> [String: Any] {
		let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
		guard let dictionary = propertyList as? [String: Any] else {
			throw ProxyConfigHelperXPCError.propertyListDecodingFailed
		}
		return dictionary
	}
}

protocol ProxyConfigHelperXPCMessage: Codable, Sendable {
	associatedtype Response: Codable & Sendable
	static var kind: String { get }
}

struct ProxyConfigHelperRequestEnvelope: Codable, Sendable {
	let kind: String
	let payload: Data
}

struct ProxyConfigHelperResponseEnvelope: Codable, Sendable {
	let kind: String
	let payload: Data
}

enum ProxyConfigHelperXPCCodec {
	private static func encoder() -> JSONEncoder {
		JSONEncoder()
	}

	private static func decoder() -> JSONDecoder {
		JSONDecoder()
	}

	static func encodeRequest<Message: ProxyConfigHelperXPCMessage>(_ message: Message) throws -> Data {
		let payload = try encoder().encode(message)
		let envelope = ProxyConfigHelperRequestEnvelope(kind: Message.kind, payload: payload)
		return try encoder().encode(envelope)
	}

	static func decodeRequestEnvelope(from data: Data) throws -> ProxyConfigHelperRequestEnvelope {
		do {
			return try decoder().decode(ProxyConfigHelperRequestEnvelope.self, from: data)
		} catch {
			throw ProxyConfigHelperXPCError.invalidRequestEnvelope
		}
	}

	static func decodeMessage<Message: ProxyConfigHelperXPCMessage>(_ type: Message.Type, from envelope: ProxyConfigHelperRequestEnvelope) throws -> Message {
		guard envelope.kind == Message.kind else {
			throw ProxyConfigHelperXPCError.unexpectedMessage(envelope.kind)
		}
		return try decoder().decode(Message.self, from: envelope.payload)
	}

	static func encodeResponse<Message: ProxyConfigHelperXPCMessage>(_ response: Message.Response, for type: Message.Type) throws -> Data {
		let payload = try encoder().encode(response)
		let envelope = ProxyConfigHelperResponseEnvelope(kind: Message.kind, payload: payload)
		return try encoder().encode(envelope)
	}

	static func decodeResponse<Message: ProxyConfigHelperXPCMessage>(_ data: Data, as type: Message.Type) throws -> Message.Response {
		let envelope: ProxyConfigHelperResponseEnvelope
		do {
			envelope = try decoder().decode(ProxyConfigHelperResponseEnvelope.self, from: data)
		} catch {
			throw ProxyConfigHelperXPCError.invalidResponseEnvelope
		}

		guard envelope.kind == Message.kind else {
			throw ProxyConfigHelperXPCError.unexpectedResponse(expected: Message.kind, actual: envelope.kind)
		}

		return try decoder().decode(Message.Response.self, from: envelope.payload)
	}
}

enum ProxyConfigHelperMessages {
	struct GetVersion: ProxyConfigHelperXPCMessage {
		static let kind = "getVersion"
		typealias Response = String
	}

	struct GetUsedPorts: ProxyConfigHelperXPCMessage {
		static let kind = "getUsedPorts"
		typealias Response = String?
	}

	struct StartMeta: ProxyConfigHelperXPCMessage {
		static let kind = "startMeta"
		typealias Response = String?

		let path: String
		let confPath: String
		let confFilePath: String
		let confJSON: String
		var coreMD5: String = ""
	}

	struct StopMeta: ProxyConfigHelperXPCMessage {
		static let kind = "stopMeta"
		typealias Response = ProxyConfigHelperExplicitSuccess
	}

	struct TerminateExistingMeta: ProxyConfigHelperXPCMessage {
		static let kind = "terminateExistingMeta"
		typealias Response = Bool
	}

	struct UpdateTun: ProxyConfigHelperXPCMessage {
		static let kind = "updateTun"
		typealias Response = ProxyConfigHelperExplicitSuccess

		let state: Bool
		let dns: String
	}

	struct FlushDnsCache: ProxyConfigHelperXPCMessage {
		static let kind = "flushDnsCache"
		typealias Response = ProxyConfigHelperExplicitSuccess
	}

	struct EnableProxy: ProxyConfigHelperXPCMessage {
		static let kind = "enableProxy"
		typealias Response = String?

		let port: Int
		let socksPort: Int
		let pac: String?
		let filterInterface: Bool
		let ignoreList: [String]
	}

	struct DisableProxy: ProxyConfigHelperXPCMessage {
		static let kind = "disableProxy"
		typealias Response = String?

		let filterInterface: Bool
	}

	struct RestoreProxy: ProxyConfigHelperXPCMessage {
		static let kind = "restoreProxy"
		typealias Response = String?

		let currentPort: Int
		let socksPort: Int
		let info: ProxyConfigHelperPropertyList
		let filterInterface: Bool
	}

	struct GetCurrentProxySetting: ProxyConfigHelperXPCMessage {
		static let kind = "getCurrentProxySetting"
		typealias Response = ProxyConfigHelperPropertyList
	}
}
