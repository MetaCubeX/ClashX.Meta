//
//  ProgressButton.swift
//  ClashX Dashboard
//
//

import SwiftUI
import AppKit

struct ProgressButton: View {
	
	@State var title: String
	@State var title2: String
	@State var iconName: String
	@Binding var inProgress: Bool
	
	@State var autoWidth = true
	
	@State var action: () -> Void
	
    var body: some View {
		Button() {
			action()
		} label: {
			HStack {
				VStack {
					if inProgress {
						ProgressView()
							.controlSize(.small)
					} else {
						Image(systemName: iconName)
					}
				}
				.frame(width: 12)

				if title != "" {
					Spacer()
					
					Text(LocalizedStringKey(inProgress ? title2 : title))
						.font(.system(size: 13))
					
					Spacer()
				}
			}
			.animation(.default, value: inProgress)
			.foregroundColor(inProgress ? .gray : .blue)
		}
		.disabled(inProgress)
		.frame(width: autoWidth ? ProgressButton.width([title, title2]) : nil)
    }
	
	static func width(_ titles: [String]) -> CGFloat {
		let str = titles.max {
			$0.count < $1.count
		} ?? ""
		
		if str == "" {
			return 12 + 8
		}
		
		let w = TextMeasurement.width(of: str, font: NSFont.systemFont(ofSize: 13))
		return w + 12 + 45
	}
}

//struct ProgressButton_Previews: PreviewProvider {
//    static var previews: some View {
//        ProgressButton()
//    }
//}
