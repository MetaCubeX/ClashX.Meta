//
//  ConnectionProxyClientCellView.swift
//  ClashX
//
//  Created by yicheng on 2023/7/6.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit

@available(macOS 10.15, *)
class ConnectionProxyClientCellView: NSView, ConnectionCellProtocol {
    let imageView = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func setupUI() {
        addSubview(nameLabel)
        addSubview(imageView)
        nameLabel.font = NSFont.systemFont(ofSize: 12)
        imageView.makeConstraints {
            [$0.heightAnchor.constraint(equalToConstant: 18),
             $0.widthAnchor.constraint(equalTo: $0.heightAnchor),
             $0.centerYAnchor.constraint(equalTo: centerYAnchor),
             $0.leadingAnchor.constraint(equalTo: leadingAnchor)]
        }
        nameLabel.makeConstraints {
            [
                $0.centerYAnchor.constraint(equalTo: centerYAnchor),
                $0.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                $0.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
            ]
        }
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.cell?.truncatesLastVisibleLine = true
    }

    func setup(with connection: ClashConnectionSnapShot.Connection, type: ConnectionColume) {
        nameLabel.stringValue = connection.metadata.processName ?? NSLocalizedString("Unknown", comment: "")
        imageView.image = connection.metadata.processImage
    }
}
