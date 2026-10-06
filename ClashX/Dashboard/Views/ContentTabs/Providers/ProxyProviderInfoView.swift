//
//  ProxyProviderInfoView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ProxyProviderInfoView: View {
	
	@ObservedObject var provider: DBProxyProvider
	@EnvironmentObject var hideProxyNames: HideProxyNames
	
	@State var withUpdateButton = false
	@State var isUpdating = false
	
    var body: some View {
		HStack {
			VStack {
				header
				content
			}
			
			if withUpdateButton {
				ProgressButton(
					title: "",
					title2: "",
					iconName: "arrow.clockwise",
					inProgress: $isUpdating) {
						Task {
							await update()
						}
					}
			}
		}
    }
	
	var header: some View {
		HStack() {
			Text(hideProxyNames.hide
				 ? HiddenNameToken.token(for: provider.name)
					: provider.name)
				.font(.system(size: 17))
			Text(verbatim: provider.vehicleType.rawValue)
				.font(.system(size: 13))
				.foregroundColor(.secondary)
			Text(String(format: NSLocalizedString("%lld", comment: ""), provider.proxies.count))
				.font(.system(size: 11))
				.padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
				.background(Color.gray.opacity(0.5))
				.cornerRadius(4)
			
			Spacer()
		}
	}
	
	var content: some View {
		VStack {
			HStack(spacing: 20) {
				Text(provider.trafficInfo)
				Text(provider.expireDate)
				Spacer()
			}
			HStack {
				Text(provider.updatedAt)
				Spacer()
			}
		}
		.font(.system(size: 12))
		.foregroundColor(.secondary)
	}

	@MainActor
	func update() async {
		isUpdating = true
		let name = provider.name
		_ = await ApiRequest.updateProvider(for: .proxy, name: name)
		let resp = await ApiRequest.requestProxyProviderList()
		if let p = resp.allProviders[provider.name] {
			provider.updateInfo(DBProxyProvider(provider: p))
		}
		isUpdating = false
	}
}

//struct ProxyProviderInfoView_Previews: PreviewProvider {
//    static var previews: some View {
//        ProxyProviderInfoView()
//    }
//}
