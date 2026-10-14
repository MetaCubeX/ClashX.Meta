import Cocoa

final class PathDiagnosticsView: NSVisualEffectView {
    var onRetry: (() -> Void)?

    private let stagesStack = NSStackView()
    private let retryButton = NSButton(title: "Run Again", target: nil, action: nil)
    private var stageViews: [PathDiagnosticStage: PathDiagnosticStageView] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .sidebar
        blendingMode = .withinWindow
        state = .active
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showChecking() {
        let now = Date()
        for stage in PathDiagnosticStage.allCases {
            stageViews[stage]?.update(PathDiagnosticResult(stage: stage,
                                                           status: .checking,
                                                           summary: "Checking",
                                                           detail: "Probe is running.",
                                                           duration: nil,
                                                           timestamp: now))
        }
        retryButton.isEnabled = false
    }

    func update(_ snapshot: PathDiagnosticsSnapshot) {
        for stage in PathDiagnosticStage.allCases {
            if let result = snapshot.results[stage] { stageViews[stage]?.update(result) }
        }
        retryButton.isEnabled = true
    }

    private func setup() {
        let title = NSTextField(labelWithString: "Current Path Diagnostics")
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor

        retryButton.bezelStyle = .rounded
        retryButton.font = NSFont.systemFont(ofSize: 11)
        retryButton.target = self
        retryButton.action = #selector(retry)

        stagesStack.orientation = .horizontal
        stagesStack.alignment = .centerY
        stagesStack.distribution = .fill
        stagesStack.spacing = 4

        for (index, stage) in PathDiagnosticStage.allCases.enumerated() {
            let stageView = PathDiagnosticStageView(stage: stage)
            stageView.widthAnchor.constraint(greaterThanOrEqualToConstant: 118).isActive = true
            stageViews[stage] = stageView
            stagesStack.addArrangedSubview(stageView)
            if index < PathDiagnosticStage.allCases.count - 1 {
                let arrow = NSTextField(labelWithString: "→")
                arrow.alignment = .center
                arrow.textColor = .tertiaryLabelColor
                arrow.font = NSFont.systemFont(ofSize: 14, weight: .medium)
                arrow.setContentHuggingPriority(.required, for: .horizontal)
                stagesStack.addArrangedSubview(arrow)
            }
        }

        addSubview(title)
        addSubview(retryButton)
        addSubview(stagesStack)
        title.translatesAutoresizingMaskIntoConstraints = false
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        stagesStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            retryButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            retryButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            stagesStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stagesStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stagesStack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            stagesStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @objc private func retry() {
        onRetry?()
    }
}

private final class PathDiagnosticStageView: NSView {
    private let stage: PathDiagnosticStage
    private let dot = NSView()
    private let titleLabel: NSTextField
    private let summaryLabel = NSTextField(labelWithString: "Not checked")
    private let statusLabel = NSTextField(labelWithString: "Inactive")
    private var result: PathDiagnosticResult?
    private var detailPopover: NSPopover?

    init(stage: PathDiagnosticStage) {
        self.stage = stage
        titleLabel = NSTextField(labelWithString: stage.title)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ result: PathDiagnosticResult) {
        self.result = result
        summaryLabel.stringValue = result.summary
        statusLabel.stringValue = result.status.displayName
        statusLabel.textColor = color(for: result.status)
        dot.layer?.backgroundColor = color(for: result.status).cgColor
        toolTip = result.detail
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        summaryLabel.font = NSFont.systemFont(ofSize: 10)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)

        for child in [dot, titleLabel, summaryLabel, statusLabel] {
            addSubview(child)
            child.translatesAutoresizingMaskIntoConstraints = false
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(showDetails))
        addGestureRecognizer(click)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dot.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5),
            titleLabel.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            summaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            statusLabel.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 2),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
        ])
    }

    @objc private func showDetails() {
        guard let result = result else { return }
        let controller = PathDiagnosticPopoverController(result: result)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        detailPopover = popover
    }

    private func color(for status: PathDiagnosticStatus) -> NSColor {
        switch status {
        case .checking: return .systemYellow
        case .healthy: return .systemGreen
        case .failed: return .systemRed
        case .blocked, .inactive: return .tertiaryLabelColor
        }
    }
}

private final class PathDiagnosticPopoverController: NSViewController {
    private let result: PathDiagnosticResult

    init(result: PathDiagnosticResult) {
        self.result = result
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 118))
        let title = NSTextField(labelWithString: "\(result.stage.title) · \(result.status.displayName)")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: result.detail)
        detail.font = NSFont.systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        let duration = result.duration.map { String(format: " · %.0f ms", $0 * 1000) } ?? ""
        let time = NSTextField(labelWithString: formatter.string(from: result.timestamp) + duration)
        time.font = NSFont.systemFont(ofSize: 10)
        time.textColor = .tertiaryLabelColor

        for child in [title, detail, time] {
            container.addSubview(child)
            child.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            time.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            time.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            time.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        view = container
    }
}
