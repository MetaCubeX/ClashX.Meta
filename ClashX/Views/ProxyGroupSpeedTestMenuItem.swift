//
//  ProxyGroupSpeedTestMenuItem.swift
//  ClashX
//
//  Created by yicheng on 2019/10/15.
//  Copyright © 2019 west2online. All rights reserved.
//

import Carbon
import Cocoa

class ProxyGroupSpeedTestMenuItem: NSMenuItem {
    let proxyGroup: ClashProxy
    let testType: TestType

    init(group: ClashProxy) {
        proxyGroup = group
        if group.type.isAutoGroup {
            testType = .reTest
        } else if group.type == .select {
            testType = .benchmark
        } else {
            testType = .unknown
        }

        super.init(title: NSLocalizedString("Benchmark", comment: ""), action: nil, keyEquivalent: "")
        target = self
        action = #selector(healthCheck)

        switch testType {
        case .benchmark:
            view = ProxyGroupSpeedTestMenuItemView(testType.title)
        case .reTest:
            title = testType.title
        case .unknown:
            assertionFailure()
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func healthCheck() {
        guard testType == .reTest else { return }
		ApiRequest.getGroupDelay(groupName: proxyGroup.name) { _ in }
        menu?.cancelTracking()
    }
}

extension ProxyGroupSpeedTestMenuItem: ProxyGroupMenuHighlightDelegate {
    func highlight(item: NSMenuItem?) {
        (view as? ProxyGroupSpeedTestMenuItemView)?.isHighlighted = item == self
    }
}

private class ProxyGroupSpeedTestMenuItemView: MenuItemBaseView {
    private let label: NSTextField

    init(_ title: String) {
        label = NSTextField(labelWithString: title)
        label.font = type(of: self).labelFont
        label.sizeToFit()
        let rect = NSRect(x: 0, y: 0, width: label.bounds.width + 40, height: 20)
        super.init(frame: rect, autolayout: false)
        addSubview(label)
        label.frame = NSRect(x: 20, y: 0, width: label.bounds.width, height: 20)
        label.textColor = NSColor.labelColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var cells: [NSCell?] {
        return [label.cell]
    }

    override var labels: [NSTextField] {
        return [label]
    }

    override func didClickView() {
        startBenchmark()
    }

    private func startBenchmark() {
        guard let group = (enclosingMenuItem as? ProxyGroupSpeedTestMenuItem)?.proxyGroup
        else { return }

        label.stringValue = NSLocalizedString("Testing", comment: "")
        enclosingMenuItem?.isEnabled = false
        setNeedsDisplay()

        // Create a dispatch group to track all proxy tests
        let dispatchGroup = DispatchGroup()
        
        // Start testing each proxy individually
        group.all?.forEach { proxyName in
            dispatchGroup.enter()
            
            ApiRequest.getProxyDelay(proxyName: proxyName) { delay in
                defer { dispatchGroup.leave() }
                
                guard let menu = self.enclosingMenuItem else { return }
                var delayStr = NSLocalizedString("fail", comment: "")
                var delayValue = 0
                if delay != 0 {
                    delayStr = "\(delay) ms"
                    delayValue = delay
                }

                // Update UI on main thread
                DispatchQueue.main.async {
                    // Update menu items directly
                    if let proxyMenu = menu.submenu {
                        for item in proxyMenu.items {
                            if let proxyItem = item as? ProxyMenuItem, proxyItem.proxyName == proxyName {
                                proxyItem.updateDelay(delayStr, rawValue: delayValue)
                            }
                        }
                    }
                    
                    // Post notification for other observers
                    NotificationCenter.default.post(
                        name: .speedTestFinishForProxy,
                        object: nil,
                        userInfo: ["proxyName": proxyName,
                                  "delay": delayStr,
                                  "rawValue": delayValue])
                }
            }
        }

        // When all tests are complete
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self, let menu = self.enclosingMenuItem else { return }
            self.label.stringValue = menu.title
            menu.isEnabled = true
            self.setNeedsDisplay()
        }
    }
}

extension ProxyGroupSpeedTestMenuItem {
    enum TestType {
        case benchmark
        case reTest
        case unknown

        var title: String {
            switch self {
            case .benchmark: return NSLocalizedString("Benchmark", comment: "")
            case .reTest: return NSLocalizedString("ReTest", comment: "")
            case .unknown: return ""
            }
        }
    }
}
