//
//  SwiftUIView.swift
//  
//
//

import SwiftUI

struct SidebarLabel: View {
	@State var item: SidebarItem
	
    var body: some View {
		HStack(spacing: 10) {
			Image(systemName: item.icon)
				.font(.system(size: 16))
				.foregroundColor(.accentColor)
				.frame(width: 18)
			Text(LocalizedStringKey(item.rawValue))
		}
		.listRowInsets(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
    }
}

struct SidebarLabel_Previews: PreviewProvider {
    static var previews: some View {
		SidebarLabel(item: .overview)
    }
}
