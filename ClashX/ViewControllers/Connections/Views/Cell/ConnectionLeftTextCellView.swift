//
//  ConnectionLeftTextCellView.swift
//  ClashX
//
//  Created by miniLV on 2023-07-10.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit

@available(macOS 10.15, *)
class ConnectionApplicationCellView: NSView {
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
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        imageView.makeConstraints {
            [$0.heightAnchor.constraint(equalToConstant: 23),
             $0.widthAnchor.constraint(equalTo: $0.heightAnchor),
             $0.centerYAnchor.constraint(equalTo: centerYAnchor),
             $0.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)]
        }
        nameLabel.makeConstraints {
            [
                $0.centerYAnchor.constraint(equalTo: centerYAnchor),
                $0.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                $0.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
            ]
        }
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.cell?.truncatesLastVisibleLine = true
    }

    func setup(with connection: ConnectionApplication) {
        nameLabel.stringValue = connection.name ?? NSLocalizedString("Unknown", comment: "")
        imageView.image = connection.image
    }
}

class ConnectionLeftTextCellView: NSView {
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
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        nameLabel.makeConstraints {
            [
                $0.centerYAnchor.constraint(equalTo: centerYAnchor),
                $0.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                $0.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
            ]
        }
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.cell?.truncatesLastVisibleLine = true
    }

    func setup(with text: String) {
        nameLabel.stringValue = text
    }
}

class ApplicationClientSectionCell: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func setupUI() {
        addSubview(titleLabel)
        titleLabel.font = NSFont.systemFont(ofSize: 10)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.makeConstraints {
            [
                $0.centerYAnchor.constraint(equalTo: centerYAnchor),
                $0.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
                $0.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
            ]
        }
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.cell?.truncatesLastVisibleLine = true
    }

    func setup(with title: String) {
        titleLabel.stringValue = title
    }
}
