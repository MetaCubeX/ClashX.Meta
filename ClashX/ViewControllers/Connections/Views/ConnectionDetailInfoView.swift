//
//  ConnectionDetailInfoView.swift
//  ClashX
//
//  Created by yicheng on 2023/7/5.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import Combine

@available(macOS 10.15, *)
class ConnectionDetailInfoView: NSView {
    private let logoView = NSImageView()
    private let processNameLabel = NSTextField(labelWithString: "")
    private let hostLabel = NSTextField(labelWithString: "")
    private let generalView = ConnectionDetailInfoGeneralView.createFromNib()
    private let containerView = NSView()
    private var cancelable = Set<AnyCancellable>()
    private let closeButton = NSButton()
    private var viewModel: ConnectionDetailViewModel?
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        updateColor()
        setupSubviews()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    func updateColor() {
        if #available(macOS 11.0, *) {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            }
        } else {
            let pervious = NSAppearance.current
            NSAppearance.current = effectiveAppearance
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            NSAppearance.current = pervious
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupSubviews() {
        addSubview(logoView)
        logoView.makeConstraints {
            [$0.topAnchor.constraint(equalTo: topAnchor, constant: 16),
             $0.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
             $0.widthAnchor.constraint(equalTo: $0.heightAnchor),
             $0.widthAnchor.constraint(equalToConstant: 36)]
        }
        let nameStackView = NSStackView()
        nameStackView.orientation = .vertical
        nameStackView.addArrangedSubview(processNameLabel)
        nameStackView.addArrangedSubview(hostLabel)
        nameStackView.alignment = .left
        nameStackView.spacing = 2
        addSubview(nameStackView)
        nameStackView.makeConstraints {
            [$0.centerYAnchor.constraint(equalTo: logoView.centerYAnchor),
             $0.leadingAnchor.constraint(equalTo: logoView.trailingAnchor, constant: 10)]
        }

        processNameLabel.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        hostLabel.font = NSFont.systemFont(ofSize: 12)
        /*
         let segmentControl = NSSegmentedControl(labels: ["General", "Event"], trackingMode: .selectOne, target: self, action: #selector(actionSelectSegment(sender: )))
         addSubview(segmentControl)
         segmentControl.makeConstraints {
             [$0.leftAnchor.constraint(equalTo: logoView.centerXAnchor),
              $0.topAnchor.constraint(equalTo: nameStackView.bottomAnchor, constant: 12)]
         }
         segmentControl.selectedSegment = 0
          */
        closeButton.title = NSLocalizedString("Close Connection", comment: "")
        closeButton.bezelStyle = .regularSquare
        closeButton.target = self
        closeButton.action = #selector(actionCloseConn)
        addSubview(closeButton)
        closeButton.makeConstraints { [
            $0.centerYAnchor.constraint(equalTo: nameStackView.centerYAnchor),
            $0.rightAnchor.constraint(equalTo: rightAnchor, constant: -12)
        ] }

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(separator)
        separator.makeConstraints {
            [$0.heightAnchor.constraint(equalToConstant: 1),
             $0.leftAnchor.constraint(equalTo: logoView.centerXAnchor),
             $0.rightAnchor.constraint(equalTo: rightAnchor),
             $0.centerYAnchor.constraint(equalTo: nameStackView.bottomAnchor, constant: 12)]
        }

        addSubview(containerView)
        containerView.makeConstraints {
            [$0.leftAnchor.constraint(equalTo: separator.leftAnchor),
             $0.rightAnchor.constraint(equalTo: rightAnchor),
             $0.bottomAnchor.constraint(equalTo: bottomAnchor),
             $0.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16)]
        }

        addGeneralView()
    }

    func setup(with viewModel: ConnectionDetailViewModel) {
        cancelable.removeAll()
        self.viewModel = viewModel
        viewModel.$processName.weakAssign(to: \.stringValue, on: processNameLabel).store(in: &cancelable)
        viewModel.$applicationPath.weakAssign(to: \.toolTip, on: processNameLabel).store(in: &cancelable)
        viewModel.$applicationPath.weakAssign(to: \.toolTip, on: logoView).store(in: &cancelable)
        viewModel.$remoteHost.weakAssign(to: \.stringValue, on: hostLabel).store(in: &cancelable)
        viewModel.$processImage.weakAssign(to: \.image, on: logoView).store(in: &cancelable)
        viewModel.$entry.weakAssign(to: \.stringValue, on: generalView.entryLabel).store(in: &cancelable)
        viewModel.$networkType.weakAssign(to: \.stringValue, on: generalView.networkTypeLabel).store(in: &cancelable)

        viewModel.$totalUpload.weakAssign(to: \.stringValue, on: generalView.totalUploadLabel).store(in: &cancelable)
        viewModel.$totalDownload.weakAssign(to: \.stringValue, on: generalView.totalDownloadLabel).store(in: &cancelable)

        viewModel.$maxUpload.weakAssign(to: \.stringValue, on: generalView.maxUploadLabel).store(in: &cancelable)
        viewModel.$maxDownload.weakAssign(to: \.stringValue, on: generalView.maxDownloadLabel).store(in: &cancelable)

        viewModel.$currentUpload.weakAssign(to: \.stringValue, on: generalView.currentUploadLabel).store(in: &cancelable)
        viewModel.$currentDownload.weakAssign(to: \.stringValue, on: generalView.currentDownloadLabel).store(in: &cancelable)

        viewModel.$rule.weakAssign(to: \.stringValue, on: generalView.ruleLabel).store(in: &cancelable)
        viewModel.$chain.weakAssign(to: \.stringValue, on: generalView.proxyChainLabel).store(in: &cancelable)
        viewModel.$sourceIP.weakAssign(to: \.stringValue, on: generalView.sourceIpLabel).store(in: &cancelable)

        viewModel.$destination.weakAssign(to: \.stringValue, on: generalView.destLabel).store(in: &cancelable)
        viewModel.$otherText.weakAssign(to: \.string, on: generalView.otherTextView).store(in: &cancelable)

        viewModel.$showCloseButton.map { !$0 }.weakAssign(to: \.isHidden, on: closeButton).store(in: &cancelable)
    }

    @objc func actionSelectSegment(sender: NSSegmentedControl?) {}
    @objc func actionCloseConn() {
        viewModel?.closeConnection()
    }

    func addGeneralView() {
        containerView.subviews.forEach { $0.removeFromSuperview() }
        containerView.addSubview(generalView)
        generalView.makeConstraintsToBindToSuperview()
    }
}
