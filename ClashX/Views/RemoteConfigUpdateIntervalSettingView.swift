//
//  RemoteConfigUpdateIntervalSettingView.swift
//  ClashX Pro
//
//  Created by yicheng on 2021/10/4.
//  Copyright © 2021 west2online. All rights reserved.
//

import AppKit
import Foundation

class RemoteConfigUpdateIntervalSettingView: NSView {
    init() {
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let stackView = NSStackView()
    let textfield = NSTextField()
    func setup() {
        stackView.addArrangedSubview(textfield)
        stackView.addArrangedSubview(NSTextField(labelWithString: NSLocalizedString("hours", comment: "")))
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22),
            textfield.widthAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        textfield.translatesAutoresizingMaskIntoConstraints = false
        textfield.stringValue = "\(Int(Settings.configAutoUpdateInterval / 3600))"
    }
}
