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

enum WebCacheCleaner {
    static func clean() {
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        Logger.log("[WebCacheCleaner] All cookies deleted")
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            records.forEach { record in
                WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {})
                Logger.log("[WebCacheCleaner] Record \(record) deleted")
            }
        }
    }
}

class ClashWebViewContoller: NSViewController {
    let webview: CustomWKWebView = .init()
    var bridge: JSBridge?
    let disposeBag = DisposeBag()
    let minSize = NSSize(width: 920, height: 580)

    let effectView = NSVisualEffectView()

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: minSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        webview.uiDelegate = self
        webview.navigationDelegate = self

        webview.customUserAgent = "ClashX Runtime"
        if #available(macOS 13.3, *) {
            webview.isInspectable = true
        }
        webview.setValue(false, forKey: "drawsBackground")
        let script = WKUserScript(source: "console.log(\"dashboard loaded\")", injectionTime: .atDocumentStart, forMainFrameOnly: false)

        webview.configuration.userContentController.addUserScript(script)

        bridge = JsBridgeUtil.initJSbridge(webview: webview, delegate: self)

        webview.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        NotificationCenter.default.rx.notification(.reloadDashboard).bind {
            [weak self] _ in
            self?.webview.reload()
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
        view.window?.toolbar = NSToolbar()
        view.window?.toolbar?.showsBaselineSeparator = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 10

        view.window?.minSize = minSize
    }

    func setupView() {
        view.addSubview(effectView)
        view.addSubview(webview)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        effectView.frame = view.bounds
        webview.frame = view.bounds
    }

    func loadWebRecourses() {
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeMemoryCache], modifiedSince: Date(timeIntervalSince1970: 0), completionHandler: {})
        // defaults write com.west2online.ClashX webviewUrl "your url"
        if let userDefineUrl = UserDefaults.standard.string(forKey: "webviewUrl"), let url = URL(string: userDefineUrl) {
            Logger.log("get user define url: \(url)")
            webview.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 0))
            return
        }
        let defaultUrl = "http://127.0.0.1:\(ConfigManager.shared.apiPort)/ui/"
        if let url = URL(string: defaultUrl) {
            Logger.log("dashboard url:\(defaultUrl)")
            webview.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 0))
            return
        }
        Logger.log("load dashboard url fail", level: .error)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        NSAlert.alert(with: message)
        completionHandler()
    }
}

extension ClashWebViewContoller: WKUIDelegate, WKNavigationDelegate {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.log("[dashboard] webview crashed", level: .error)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        Logger.log("[dashboard] load request \(String(describing: navigationAction.request.url?.absoluteString))", level: .debug)
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.log("[dashboard] didFinish \(String(describing: navigation))", level: .info)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.log("[dashboard] \(String(describing: navigation)) error: \(error)", level: .error)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

class CustomWKWebView: WKWebView {
    var dragableAreaHeight: CGFloat = 30
    let alwaysDragableLeftAreaWidth: CGFloat = 150

    private func isInDargArea(with event: NSEvent?) -> Bool {
        guard let event = event else { return false }
        let x = event.locationInWindow.x
        let y = (window?.frame.size.height ?? 0) - event.locationInWindow.y
        return x < alwaysDragableLeftAreaWidth || y < dragableAreaHeight
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        if isInDargArea(with: event) {
            return true
        }
        return super.acceptsFirstMouse(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if isInDargArea(with: event) {
            window?.performDrag(with: event)
        }
    }
}
