//
//  ConnectionsViewController.swift
//  ClashX
//
//  Created by yicheng on 2023/7/5.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import Combine

@available(macOS 10.15, *)
class ConnectionsViewController: NSViewController {
    let viewModel = ConnectionsViewModel()
    let leftViewModel = ConnectionLeftPannelViewModel()
    lazy var leftTableView = ConnectionLeftPannelView(viewModel: leftViewModel)
    let topViewModel = ConnectionTopListViewModel()
    lazy var topView = ConnectionTopListView(viewModel: topViewModel)
    let detailView = ConnectionDetailInfoView()

    let connectionDetailViewModel = ConnectionDetailViewModel()

    var disposeBag = Set<AnyCancellable>()
    var modeCancellable = Set<AnyCancellable>()
    var leftWidthConstraint: NSLayoutConstraint?
    var topViewBottomConstraint: NSLayoutConstraint?
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        setupCommonViewModel()
        setupAllConnViewModel()
    }

    override func loadView() {
        view = ConnectionsViewControllerBaseView(frame: NSRect(origin: .zero, size: CGSize(width: 900, height: 600)))
    }

    private func setup() {
        view.addSubview(leftTableView)
        view.makeConstraints {
            [$0.widthAnchor.constraint(greaterThanOrEqualToConstant: 900),
             $0.heightAnchor.constraint(greaterThanOrEqualToConstant: 600)]
        }

        leftWidthConstraint = leftTableView.widthAnchor.constraint(equalToConstant: 200)
        leftTableView.makeConstraints {
            [$0.leftAnchor.constraint(equalTo: view.leftAnchor),
             $0.topAnchor.constraint(equalTo: view.topAnchor),
             $0.bottomAnchor.constraint(equalTo: view.bottomAnchor),
             leftWidthConstraint!]
        }

        (view as! ConnectionsViewControllerBaseView).leftWidthConstraint = leftWidthConstraint

        view.addSubview(topView)
        topView.makeConstraints {
            [$0.leftAnchor.constraint(equalTo: leftTableView.rightAnchor),
             $0.topAnchor.constraint(equalTo: view.topAnchor),
             $0.rightAnchor.constraint(equalTo: view.rightAnchor)]
        }
        topViewBottomConstraint = topView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        detailView.setup(with: connectionDetailViewModel)
    }

    private func setupCommonViewModel() {
        topViewModel.onSelectedConnection = { [weak self] in
            self?.viewModel.selectedConnection = $0
        }

        viewModel.$selectedConnection.sink { [weak self] conn in
            self?.connectionDetailViewModel.accept(connection: conn)
        }.store(in: &disposeBag)

        leftViewModel.onSelectedFilter = { [weak topViewModel] in
            topViewModel?.applicationFilter = $0
        }

        viewModel.$showBottomView.removeDuplicates().sink { [weak self] show in
            guard let self else { return }
            if show {
                view.addSubview(detailView)
                topViewBottomConstraint?.isActive = false
                detailView.makeConstraints {
                    [$0.leftAnchor.constraint(equalTo: self.leftTableView.rightAnchor),
                     $0.heightAnchor.constraint(equalToConstant: 236),
                     $0.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                     $0.rightAnchor.constraint(equalTo: self.view.rightAnchor),
                     $0.topAnchor.constraint(equalTo: self.topView.bottomAnchor)]
                }
            } else {
                detailView.removeFromSuperview()
                topViewBottomConstraint?.isActive = true
            }
        }.store(in: &disposeBag)
    }

    private func setupAllConnViewModel() {
        viewModel.connectionDataDidRefresh.sink { [weak topViewModel] in
            topViewModel?.connectionDidUpdate()
        }.store(in: &modeCancellable)

        viewModel.$connections.map { Array($0.values) }.sink { [weak self] in
            self?.topViewModel.accept(connections: $0)
        }.store(in: &modeCancellable)

        viewModel.$applicationMap.map { Array($0.values) }.sink { [weak self] in
            self?.leftViewModel.accept(connections: $0)
        }.store(in: &modeCancellable)

        viewModel.$sourceIPs.map { Array($0) }.sink { [weak self] in
            self?.leftViewModel.accept(sources: $0)
        }.store(in: &modeCancellable)

        viewModel.$hosts.map { Array($0) }.sink { [weak self] in
            self?.leftViewModel.accept(hosts: $0)
        }.store(in: &modeCancellable)
    }

    private func setupActiveConnViewModel() {
        viewModel.connectionDataDidRefresh.sink { [weak self] in
            guard let self else { return }
            topViewModel.accept(connections: viewModel.currentConnections)
            leftViewModel.accept(apps: viewModel.currentApplications, sources: viewModel.currentSourceIPs, hosts: viewModel.currentHosts)
        }.store(in: &modeCancellable)
        viewModel.connectionDataDidRefresh.send()
    }

    func setActiveMode(enable: Bool) {
        modeCancellable.removeAll()
        viewModel.activeOnlyMode = enable
        if viewModel.activeOnlyMode {
            setupActiveConnViewModel()
        } else {
            setupAllConnViewModel()
        }
    }
}

@available(macOS 10.15, *)
extension ConnectionsViewController: DashboardSubViewControllerProtocol {
    func actionSearch(string: String) {
        topViewModel.textFilter = string
    }
}

class ConnectionsViewControllerBaseView: NSView {
    var leftWidthConstraint: NSLayoutConstraint?
    enum DragType {
        case none
        case leftPannel
    }

    var dragType = DragType.none
    let dragSize: CGFloat = 5.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if dragType == .none {
            return super.hitTest(point)
        }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved,
                                                 .mouseEnteredAndExited,
                                                 .activeAlways],
                                       owner: self))
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        update(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragType = .none
    }

    override func mouseMoved(with event: NSEvent) {
        update(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        switch dragType {
        case .none:
            break
        case .leftPannel:
            let deltaX = event.deltaX
            let target = (leftWidthConstraint?.constant ?? 0) + deltaX
            leftWidthConstraint?.constant = min(max(target, 200), 400)
        }
    }

    func update(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        let currentLeftSize = leftWidthConstraint?.constant ?? 0
        if locationInView.x > currentLeftSize - dragSize && locationInView.x < currentLeftSize + dragSize {
            dragType = .leftPannel
            NSCursor.resizeLeftRight.set()
            return
        }
        dragType = .none
        NSCursor.arrow.set()
    }
}
