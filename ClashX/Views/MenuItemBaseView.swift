//
//  MenuItemBaseView.swift
//  ClashX
//
//  Created by yicheng on 2019/11/1.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

class MenuItemBaseView: NSView {
    private var isMouseInsideView = false
    private var isMenuOpen = false
    private let autolayout: Bool

    // MARK: Public

    var isHighlighted: Bool = false {
        didSet {
            if isHighlighted != oldValue {
                setNeedsDisplay()
            }
        }
    }

    let effectView: NSView = {
        if #available(macOS 26, *) {
            // NSGlassEffectContainerView ?
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            return view
        } else {
            let effectView = NSVisualEffectView()
            effectView.material = .popover
            effectView.state = .active
            effectView.isEmphasized = true
            effectView.blendingMode = .behindWindow
            return effectView
        }
    }()

    var cells: [NSCell?] {
        assertionFailure("Please override")
        return []
    }

    var labels: [NSTextField] {
        return []
    }

    static let menuBarHeight: CGFloat = {
        if #available(macOS 11, *) {
            return 22
        } else {
            return 20
        }
    }()

    static let labelFont: NSFont = {
        if #available(macOS 11, *) {
            return NSFont.menuFont(ofSize: 0)
        }
        return NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
    }()

    init(frame frameRect: NSRect = NSRect(x: 0, y: 0, width: 0, height: menuBarHeight), autolayout: Bool) {
        self.autolayout = autolayout
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setNeedsDisplay() {
        needsDisplay = true
    }

    func didClickView() {
        assertionFailure("Please override this method")
    }

    // MARK: Private

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: type(of: self).menuBarHeight).isActive = true
        // background
        addSubview(effectView)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 11, *) {
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = 3
            effectView.layer?.masksToBounds = true
        }
        if autolayout {
            let padding: CGFloat
            if #available(macOS 11, *) {
                padding = 5
            } else {
                padding = 0
            }
            effectView.leftAnchor.constraint(equalTo: leftAnchor, constant: padding).isActive = true
            effectView.rightAnchor.constraint(equalTo: rightAnchor, constant: -padding).isActive = true
            effectView.topAnchor.constraint(equalTo: topAnchor).isActive = true
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        }
    }

    // MARK: Override

    override func layout() {
        super.layout()
        if !autolayout {
            if #available(macOS 11, *) {
                effectView.frame = CGRect(x: 5, y: 0, width: bounds.width - 10, height: bounds.height)
            } else {
                effectView.frame = bounds
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        syncMenuAppearance()
        let enabled = enclosingMenuItem?.isEnabled ?? true
        let highlighted = isHighlighted && enabled
        updateLabelColors(highlighted: highlighted, enabled: enabled)
        setHighlighted(highlighted)
        cells.forEach { $0?.backgroundStyle = isHighlighted ? .emphasized : .normal }
    }

    /// Subclasses override this to own their text colors. Default covers the
    /// common single-color case (`labels`).
    /// macOS 26 has no NSVisualEffectView carrier, backgroundStyle alone
    /// does not reliably invert flat (allowsVibrancy=false) text, so set it explicitly.
    func updateLabelColors(highlighted: Bool, enabled: Bool) {
        if highlighted {
            labels.forEach { $0.textColor = NSColor.alternateSelectedControlTextColor }
        } else {
            labels.forEach { $0.textColor = enabled ? NSColor.labelColor : NSColor.placeholderTextColor }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let newWindow = newWindow, !newWindow.isKeyWindow {
            newWindow.becomeKey()
        }
        syncMenuAppearance(fallbackWindow: newWindow)
        updateTrackingAreas()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard autolayout else { return }
        if #unavailable(macOS 10.15) {
            if let view = superview {
                view.autoresizingMask = [.width]
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
    }

    override func mouseUp(with event: NSEvent) {
        Task { @MainActor in
            self.didClickView()
        }
    }
    
    func setHighlighted(_ isHighlighted: Bool) {
        if #available(macOS 26, *) {
            effectView.layer?.backgroundColor = isHighlighted ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        } else {
            (effectView as? NSVisualEffectView)?.material = isHighlighted ? .selection : .popover
        }
    }

    /// On macOS 26 the menu content is a plain clear NSView, so flat
    /// (allowsVibrancy=false) labels must resolve labelColor against the menu
    /// window's appearance. Otherwise a light appearance resolves to black on a
    /// dark translucent menu, while emoji color-glyphs stay visible.
    /// Appearance is synced for every NSTextField in the hierarchy so subclasses
    /// don't need to expose their labels for this.
    private func syncMenuAppearance(fallbackWindow: NSWindow? = nil) {
        if #available(macOS 26, *) {
            let source = fallbackWindow?.effectiveAppearance ?? window?.effectiveAppearance
            guard let source else { return }
            if effectView.appearance !== source {
                effectView.appearance = source
            }
            for label in allMenuTextFields() where label.appearance !== source {
                label.appearance = source
            }
        }
    }

    private func allMenuTextFields() -> [NSTextField] {
        var out: [NSTextField] = []
        func visit(_ view: NSView) {
            for sub in view.subviews {
                if let field = sub as? NSTextField {
                    out.append(field)
                }
                visit(sub)
            }
        }
        visit(self)
        return out
    }
}
