//
//  ConnectionStatusIconCellView.swift
//  ClashX
//
//  Created by yicheng on 2023/7/6.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import Combine

@available(macOS 10.15, *)
class ConnectionStatusIconCellView: NSView, ConnectionCellProtocol {
    let imageView = NSImageView()
    var cancellable = Set<AnyCancellable>()
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func setupUI() {
        addSubview(imageView)
        imageView.makeConstraints {
            [$0.heightAnchor.constraint(equalToConstant: 18),
             $0.widthAnchor.constraint(equalTo: $0.heightAnchor),
             $0.centerYAnchor.constraint(equalTo: centerYAnchor),
             $0.leadingAnchor.constraint(equalTo: leadingAnchor)]
        }
    }

    func setup(with connection: ClashConnectionSnapShot.Connection, type: ConnectionColume) {
        cancellable.removeAll()
        connection
            .$status
            .map(\.image)
            .weakAssign(to: \.image, on: imageView)
            .store(in: &cancellable)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancellable.removeAll()
    }
}
