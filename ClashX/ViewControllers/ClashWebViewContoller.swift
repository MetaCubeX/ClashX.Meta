//
//  ClashWebViewContoller.swift
//  ClashX
//
//  Created by yicheng on 2018/8/28.
//  Copyright © 2018年 west2online. All rights reserved.
//

import Cocoa
import RxCocoa
import RxSwift
import WebKit
import WebViewJavascriptBridge

class ClashWebViewWindowController: NSWindowController {
    var onWindowClose: (() -> Void)?

    static func create() -> ClashWebViewWindowController {
        let win = NSWindow()
        win.center()
        let wc = ClashWebViewWindowController(window: win)
        wc.contentViewController = ClashWebViewContoller()
        return wc
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(self)
        window?.delegate = self
    }
}

extension ClashWebViewWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let contentVC = contentViewController as? ClashWebViewContoller, let win = window {
            if !win.styleMask.contains(.fullScreen) {
                contentVC.lastSize = win.frame.size
            }
            contentVC.teardown()
        }
        contentViewController = nil
        onWindowClose?()
    }
}

class ClashWebViewContoller: NSViewController {
    var webview: CustomWKWebView! = CustomWKWebView()
    let diagnosticsView = PathDiagnosticsView()
    private lazy var diagnosticsService = PathDiagnosticsService(prober: SystemPathDiagnosticsProber())
    private let diagnosticsHeight: CGFloat = 104
    var bridge: WebViewJavascriptBridge?
    let disposeBag = DisposeBag()
    let minSize = NSSize(width: 920, height: 580)
    var lastSize: CGSize? {
        set {
            if let size = newValue {
                UserDefaults.standard.set(NSStringFromSize(size), forKey: "ClashWebViewContoller.lastSize")
            }
        }
        get {
            if let str = UserDefaults.standard.value(forKey: "ClashWebViewContoller.lastSize") as? String {
                return NSSizeFromString(str) as CGSize
            }
            return nil
        }
    }

    let effectView = NSVisualEffectView()

    static func createWindowController() -> NSWindowController {
        let sb = NSStoryboard(name: "Main", bundle: Bundle.main)
        let vc = sb.instantiateController(withIdentifier: "ClashWebViewContoller") as! ClashWebViewContoller
        let wc = NSWindowController(window: NSWindow())
        wc.contentViewController = vc
        return wc
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: minSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        webview.uiDelegate = self
        webview.navigationDelegate = self

        webview.customUserAgent = "ClashX Runtime"

        if NSAppKitVersion.current.rawValue > 1500 {
            webview.setValue(false, forKey: "drawsBackground")
        } else {
            webview.setValue(true, forKey: "drawsTransparentBackground")
        }

        bridge = JsBridgeUtil.initJSbridge(webview: webview, delegate: self)
        registerExtenalJSBridgeFunction()

        webview.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        NotificationCenter.default.rx.notification(.configFileChange).bind {
            [weak self] _ in
            self?.bridge?.callHandler("onConfigChange")
        }.disposed(by: disposeBag)

        NotificationCenter.default.rx.notification(.reloadDashboard).bind {
            [weak self] _ in
            self?.webview.reload()
        }.disposed(by: disposeBag)

        diagnosticsView.onRetry = { [weak self] in
            self?.runPathDiagnostics()
        }

        Observable.merge(
            NotificationCenter.default.rx.notification(.systemNetworkStatusDidChange),
            NotificationCenter.default.rx.notification(.systemNetworkStatusIPUpdate)
        )
        .debounce(.milliseconds(500), scheduler: MainScheduler.instance)
        .bind { [weak self] _ in
            self?.runPathDiagnostics()
        }.disposed(by: disposeBag)

        loadWebRecourses()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.titleVisibility = .hidden
        view.window?.titlebarAppearsTransparent = true
        view.window?.styleMask.insert(.fullSizeContentView)

        view.window?.isOpaque = false
        view.window?.backgroundColor = NSColor.clear
        view.window?.styleMask.insert(.closable)
        view.window?.styleMask.insert(.resizable)
        view.window?.styleMask.insert(.miniaturizable)
        if #available(OSX 10.13, *) {
            view.window?.toolbar = NSToolbar()
            view.window?.toolbar?.showsBaselineSeparator = false
            view.wantsLayer = true
            view.layer?.cornerRadius = 10
        }

        view.window?.minSize = minSize
        if let lastSize = lastSize, lastSize != .zero {
            view.window?.setContentSize(lastSize)
        }
        view.window?.center()
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        runPathDiagnostics()
    }

    func setupView() {
        view.addSubview(effectView)
        view.addSubview(diagnosticsView)
        view.addSubview(webview)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        effectView.frame = view.bounds
        diagnosticsView.frame = NSRect(x: 0,
                                       y: max(0, view.bounds.height - diagnosticsHeight),
                                       width: view.bounds.width,
                                       height: diagnosticsHeight)
        webview.frame = NSRect(x: 0,
                               y: 0,
                               width: view.bounds.width,
                               height: max(0, view.bounds.height - diagnosticsHeight))
    }

    func loadWebRecourses() {
        // defaults write com.west2online.ClashX webviewUrl "your url"
        let defaultUrl = "http://127.0.0.1:\(ConfigManager.shared.apiPort)/ui/"
        let url = UserDefaults.standard.string(forKey: "webviewUrl") ?? defaultUrl
        if let url = URL(string: url) {
            webview.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 0))
        }
    }

    deinit {
        teardown()
        NSApp.setActivationPolicy(.accessory)
    }

    func teardown() {
        diagnosticsService.cancel()
        guard let webview = webview else { return }
        bridge?.setWebViewDelegate(nil)
        bridge = nil
        webview.stopLoading()
        webview.navigationDelegate = nil
        webview.uiDelegate = nil
        webview.configuration.userContentController.removeAllUserScripts()
        webview.loadHTMLString("", baseURL: nil)
        webview.removeFromSuperview()
        self.webview = nil
    }

    private func runPathDiagnostics() {
        diagnosticsView.showChecking()
        diagnosticsService.run { [weak self] snapshot in
            for stage in PathDiagnosticStage.allCases {
                guard let result = snapshot.results[stage] else { continue }
                let duration = result.duration.map { String(format: " %.0fms", $0 * 1000) } ?? ""
                Logger.log("[PathDiagnostics] \(stage.title) \(result.status.displayName)\(duration)", level: result.status == .failed ? .error : .info)
            }
            DispatchQueue.main.async {
                self?.diagnosticsView.update(snapshot)
            }
        }
    }
}

extension ClashWebViewContoller {
    func registerExtenalJSBridgeFunction() {
        bridge?.registerHandler("setDragAreaHeight") {
            [weak self] anydata, responseCallback in
            if let height = anydata as? CGFloat {
                self?.webview.dragableAreaHeight = height
            }
            responseCallback?(nil)
        }
    }
}

extension ClashWebViewContoller: WKUIDelegate, WKNavigationDelegate {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {}

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.log("\(String(describing: navigation))", level: .debug)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.log("\(error)", level: .debug)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

extension ClashWebViewContoller: WebResourceLoadDelegate {}

class CustomWKWebView: WKWebView {
    var dragableAreaHeight: CGFloat = 30
    let alwaysDragableLeftAreaWidth: CGFloat = 150

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let x = event.locationInWindow.x
        let y = (window?.frame.size.height ?? 0) - event.locationInWindow.y

        if x < alwaysDragableLeftAreaWidth || y < dragableAreaHeight {
            window?.performDrag(with: event)
        }
    }
}
