//
//  ProxyNodeView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ProxyNodeView: View {
	
	@ObservedObject var proxy: DBProxy
	@State var selectable: Bool
	@Binding var now: String?
	
	@EnvironmentObject var hideProxyNames: HideProxyNames
	
	
	init(proxy: DBProxy, selectable: Bool, now: Binding<String?> = .init(get: {nil}) { _ in }) {
		self.proxy = proxy
		self.selectable = selectable
		self._now = now
		self.isBuiltInProxy = [.pass, .direct, .reject].contains(proxy.type)
	}
	
	@State private var isBuiltInProxy: Bool
	@State private var mouseOver = false
	
	var body: some View {
		VStack {
			HStack(alignment: .center) {
				Text(hideProxyNames.hide
					 ? HiddenNameToken.token(for: proxy.name)
					 : proxy.name)
					.truncationMode(.tail)
					.lineLimit(1)
				Spacer(minLength: 6)
				
				Text(proxy.udpString)
					.foregroundColor(.secondary)
					.font(.system(size: 11))
					.show(isVisible: !isBuiltInProxy)
			}
			
			Spacer(minLength: 6)
				.show(isVisible: !isBuiltInProxy)
			HStack(alignment: .center) {
				Text(verbatim: proxy.type.rawString)
					.foregroundColor(.secondary)
					.font(.system(size: 12))
				
				Text("[TFO]")
					.font(.system(size: 9))
					.show(isVisible: proxy.tfo)
				Spacer(minLength: 6)
				Text(proxy.delayString)
					.foregroundColor(proxy.delayColor)
					.font(.system(size: 11))
			}
		.show(isVisible: !isBuiltInProxy)
	}
	.onHover {
			guard selectable else { return }
			mouseOver = $0
		}
		.frame(height: 34)
		.padding(12)
		.overlay(
			RoundedRectangle(cornerRadius: 6)
				.stroke({
					if mouseOver, now == proxy.name {
						return Color.accentColor
					} else if mouseOver {
						return Color.accentColor.opacity(0.7)
					} else {
						return Color.clear
					}
				}(), lineWidth: 2)
				.padding(1)
		)
		
		.background(now == proxy.name ? DashboardTheme.cellSelectedBackground : Color("SwiftUI Colors/ContentBackgroundColor"))
	}
}

//struct ProxyNodeView_Previews: PreviewProvider {
//    static var previews: some View {
//        ProxyNodeView()
//    }
//}
