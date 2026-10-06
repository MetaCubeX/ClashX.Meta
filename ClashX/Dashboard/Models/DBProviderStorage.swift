//
//  DBProviderStorage.swift
//  ClashX Dashboard
//
//

import Cocoa
import SwiftUI

class DBProviderStorage: ObservableObject {
	@Published var proxyProviders = [DBProxyProvider]()
	@Published var ruleProviders = [DBRuleProvider]()

	init() {}
	
}

class DBProxyProvider: ObservableObject, Identifiable {
	let id = UUID().uuidString
	
	@Published var name: ClashProviderName
	@Published var proxies: [DBProxy]
	@Published var type: ClashProvider.ProviderType
	@Published var vehicleType: ClashProviderVehicleType

	@Published var trafficInfo: String
	@Published var trafficPercentage: String
	@Published var expireDate: String
	@Published var updatedAt: String
	@Published var subscriptionUsage: SubscriptionUsage?

	init(provider: ClashProvider) {
		name = provider.name
		proxies = provider.proxies.map(DBProxy.init)
		type = provider.type
		vehicleType = provider.vehicleType
		subscriptionUsage = SubscriptionUsage(info: provider.subscriptionInfo)
		
		if let info = provider.subscriptionInfo {
			let used = info.download + info.upload
			let total = info.total

			// Unlimited plans report total == 0; guard the percentage math.
			if total > 0 {
				let trafficRate = String(format: "%.2f", Double(used) / Double(total) * 100)
				trafficInfo = ByteFormat.quota(used)
				+ " / "
				+ ByteFormat.quota(total)
				+ " ( \(trafficRate)% )"
				self.trafficPercentage = trafficRate + "%"
			} else {
				trafficInfo = ByteFormat.quota(used)
				self.trafficPercentage = "0.0%"
			}
			
			let expire = info.expire
			if expire == 0 {
				expireDate = String(format: NSLocalizedString("Expire: %@", comment: ""), NSLocalizedString("none", comment: ""))
			} else {
				let eDate = Date(timeIntervalSince1970: TimeInterval(expire))
				if #available(macOS 12.0, *) {
					expireDate = String(format: NSLocalizedString("Expire: %@", comment: ""), eDate.formatted())
				} else {
					let dateFormatter = DateFormatter()
					dateFormatter.dateStyle = .short
					dateFormatter.timeStyle = .short
					expireDate = String(format: NSLocalizedString("Expire: %@", comment: ""), dateFormatter.string(from: eDate))
				}
			}

		} else {
			trafficInfo = ""
			expireDate = ""
			trafficPercentage = "0.0%"
		}
		
        self.updatedAt = DashboardFormatters.providerUpdateText(for: provider.updatedAt)
	}
	
	func updateInfo(_ new: DBProxyProvider) {
		proxies = new.proxies
		updatedAt = new.updatedAt
		expireDate = new.expireDate
		trafficInfo = new.trafficInfo
		trafficPercentage = new.trafficPercentage
		subscriptionUsage = new.subscriptionUsage
	}
}

// Normalized subscription usage; nil when data is missing or non-standard
// (mihomo passes through unparsable or negative userinfo values).
struct SubscriptionUsage: Equatable {
	let usedText: String
	let totalText: String
	let percentText: String
	let ratio: CGFloat

	init?(info: ClashProviderSubInfo?) {
		guard let info,
		      info.upload >= 0,
		      info.download >= 0,
		      info.total > 0 else { return nil }
		let used = info.upload + info.download
		guard used >= 0 else { return nil }

		usedText = ByteFormat.quota(used)
		totalText = ByteFormat.quota(info.total)
		ratio = min(CGFloat(used) / CGFloat(info.total), 1)
		let percent = Int((Double(used) / Double(info.total) * 100).rounded())
		percentText = String(format: "%d%%", percent)
	}
}

class DBRuleProvider: ObservableObject, Identifiable {
	let id: String
	
	@Published var name: ClashProviderName
	@Published var ruleCount: Int
	@Published var behavior: String
	@Published var type: String
    @Published var vehicleType: ClashProviderVehicleType
	@Published var updatedAt: Date
	
	init(provider: ClashRuleProvider) {
		id = UUID().uuidString
		
		name = provider.name
		ruleCount = provider.ruleCount
		behavior = provider.behavior
		type = provider.type
        vehicleType = provider.vehicleType
		updatedAt = provider.updatedAt
	}
}
