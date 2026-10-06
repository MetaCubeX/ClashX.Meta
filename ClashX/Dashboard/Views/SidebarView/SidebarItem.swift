//
//  SidebarItem.swift
//  ClashX Dashboard
//
//

import Cocoa
import SwiftUI

enum SidebarItem: String, Identifiable, CaseIterable {
    var id: String {
        self.rawValue
    }
    
	case overview = "Overview"
	case proxies = "Proxies"
	case rules = "Rules"
	case conns = "Conns"
	case config = "Config"
	case logs = "Logs"
    
    var icon: String {
        switch self {
        case .overview:
            "chart.bar.xaxis"
		case .proxies:
			"globe.asia.australia"
		case .rules:
			"waveform.and.magnifyingglass"
        case .conns:
            "app.connected.to.app.below.fill"
        case .config:
            "slider.horizontal.3"
        case .logs:
            "wand.and.stars.inverse"
        }
    }
}
