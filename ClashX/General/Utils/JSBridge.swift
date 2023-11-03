//
//  JSBridge.swift
//  ClashX
//
//  Created by yicheng on 2023/9/26.
//  Copyright © 2023 west2online. All rights reserved.
//

import Foundation
import WebKit

class JSBridge: NSObject {
    typealias ResponseCallback = (Any?) -> Void
    typealias BridgeHandler = (Any?, @escaping ResponseCallback) -> Void

    private weak var webView: WKWebView?
    private var handlers = [String: BridgeHandler]()
    init(_ webView: WKWebView) {
        self.webView = webView
        super.init()
        setup()
    }

    deinit {
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "jsBridge")
    }

    private func setup() {
        addScriptMessageHandler()
    }

    private func addScriptMessageHandler() {
        let scriptMessageHandler = ClashScriptMessageHandler(delegate: self)
        webView?.configuration.userContentController.add(scriptMessageHandler, name: "jsBridge")
    }

    private func sendBackMessage(data: Any?, eventID: String) {
        let data = ["id": eventID, "data": data, "type": "jsBridge"] as [String: Any?]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8)!
            let str = "window.postMessage(\(jsonString), window.origin);"
            webView?.evaluateJavaScript(str)
        } catch let err {
            Logger.log(err.localizedDescription, level: .warning)
        }
    }

    func registerHandler(_ name: String, handler: @escaping BridgeHandler) {
        handlers[name] = handler
    }
}

extension JSBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if
            let body = message.body as? [String: Any],
            let handlerName = body["name"] as? String,
            let handler = handlers[handlerName],
            let eventID = body["id"] as? String {
            let data = body["data"]
            handler(data) { [weak self] res in
                self?.sendBackMessage(data: res, eventID: eventID)
            }
        }
    }
}

private class ClashScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    public init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
