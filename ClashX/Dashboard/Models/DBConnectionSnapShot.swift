//
//  DBConnectionSnapShot.swift
//  ClashX Dashboard
//
//

import Cocoa

struct DBConnectionSnapShot: Codable {
	let downloadTotal: Int
	let uploadTotal: Int
    let connections: [DBConnection]
}

struct DBConnection: Codable, Hashable {
	let id: String
	let chains: [String]
	let upload: Int64
	let download: Int64
	let start: Date
	let rule: String
	let rulePayload: String
	
	let metadata: DBMetaConnectionData
}

struct DBMetaConnectionData: Codable, Hashable {
	let uid: Int
	
	let network: String
	let type: String
	let sourceIP: String
	let destinationIP: String
	let sourcePort: String
	let destinationPort: String
	let inboundIP: String
	let inboundPort: String
	let inboundName: String
	let host: String
	let dnsMode: String
	let process: String
	let processPath: String
	let specialProxy: String
	let specialRules: String
	let remoteDestination: String
	let sniffHost: String
	
}


class DBConnectionObject: NSObject {
	@objc let id: String
	@objc let host: String
	@objc let sniffHost: String
	@objc let process: String
	@objc let download: Int64
	@objc let upload: Int64
	let downloadString: String
	let uploadString: String
	let chains: [String]
	@objc let chainString: String
	@objc let ruleString: String
	@objc let startDate: Date
	let startString: String
	@objc let source: String
	@objc let destinationIP: String?
	@objc let type: String
	
	@objc var downloadSpeed: Int64
	@objc var uploadSpeed: Int64
	var downloadSpeedString: String
	var uploadSpeedString: String
	
	
	func isContentEqual(to source: DBConnectionObject) -> Bool {
		download == source.download &&
		upload == source.upload &&
		startString == source.startString
	}
	
	init(_ conn: DBConnection) {
		let startFormatter = DashboardFormatters.relativeDateTimeShort

		let metadata = conn.metadata

		id = conn.id
		host = "\(metadata.host == "" ? metadata.destinationIP : metadata.host):\(metadata.destinationPort)"
		sniffHost = metadata.sniffHost == "" ? "-" : metadata.sniffHost
		process = metadata.process
		download = conn.download
		downloadString = ByteFormat.total(conn.download, precision: .integer)
		upload = conn.upload
		uploadString = ByteFormat.total(conn.upload, precision: .integer)
		chains = conn.chains
		chainString = conn.chains.reversed().joined(separator: "/")
		ruleString = conn.rulePayload == "" ? conn.rule : "\(conn.rule) :: \(conn.rulePayload)"
		startDate = conn.start
		startString = startFormatter.localizedString(for: conn.start, relativeTo: Date())
		source = "\(metadata.sourceIP):\(metadata.sourcePort)"
		destinationIP = [metadata.remoteDestination,
						 metadata.destinationIP,
						 metadata.host].first(where: { $0 != "" })
		
		type = "\(metadata.type)(\(metadata.network))"
		
		downloadSpeed = 0
		uploadSpeed = 0
		downloadSpeedString = "-"
		uploadSpeedString = "-"
	}
	
	
	func updateSpeeds(_ old: (download: Int64, upload: Int64)?) {
		guard let old = old else {
			downloadSpeed = 0
			uploadSpeed = 0
			downloadSpeedString = "-"
			uploadSpeedString = "-"
			return
		}

		downloadSpeed = download - old.download
		uploadSpeed = upload - old.upload

		if downloadSpeed > 0 {
			downloadSpeedString = ByteFormat.rate(Int(downloadSpeed))
		} else {
			downloadSpeed = 0
			downloadSpeedString = "-"
		}

		if uploadSpeed > 0 {
			uploadSpeedString = ByteFormat.rate(Int(uploadSpeed))
		} else {
			uploadSpeed = 0
			uploadSpeedString = "-"
		}
	}
}
