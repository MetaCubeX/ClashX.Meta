//
//  LoginServiceKit.swift
//
//  LoginServiceKit
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

//
//  Some code copyright 2009 Naotaka Morimoto.
//
//    Much of this code was taken and adapted from GTMLoginItems of Google
//    Toolbox for Mac and QSBPreferenceWindowController of Quick Search Box
//    for the Mac by Google Inc.
//    This code is also released under Apache License, Version 2.0.
//

//  Copyright (c) 2008-2009 Google Inc. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are
//  met:
//
//    * Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
//  copyright notice, this list of conditions and the following disclaimer
//  in the documentation and/or other materials provided with the
//  distribution.
//    * Neither the name of Google Inc. nor the names of its
//  contributors may be used to endorse or promote products derived from
//  this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
//  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import Cocoa
import ServiceManagement

public enum LoginServiceKit {
    private static var snapshot: (list: LSSharedFileList, items: [LSSharedFileListItem])? {
        guard let list = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)?.takeRetainedValue() else {
            return nil
        }
        return (list, (LSSharedFileListCopySnapshot(list, nil)?.takeRetainedValue() as? [LSSharedFileListItem]) ?? [])
    }

    public static func isExistLoginItems(at path: String = Bundle.main.bundlePath) -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return loginItem(at: path) != nil
    }

    @discardableResult
    public static func addLoginItems(at path: String = Bundle.main.bundlePath) -> Bool {
        guard isExistLoginItems(at: path) == false else {
            return false
        }

        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                return true
            } catch let err {
                Logger.log("add loginItem error: \(err.localizedDescription)", level: .error)
                return false
            }
        }

        guard let (list, _) = snapshot else {
            return false
        }
        let res = LoginKitWrapper.setLogin(list, path: path)
        Logger.log("set launch at login success: \(res)")
        return res
    }

    @discardableResult
    public static func removeLoginItems(at path: String = Bundle.main.bundlePath) -> Bool {
        guard isExistLoginItems(at: path) == true else {
            return false
        }

        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                return true
            } catch let err {
                Logger.log("remove loginItem error: \(err.localizedDescription)", level: .error)
                return false
            }
        }
        guard let (list, items) = snapshot else {
            return false
        }
        return items.filter({
            LSSharedFileListItemCopyResolvedURL($0, 0, nil)?.takeRetainedValue() == (URL(fileURLWithPath: path) as CFURL) }
        ).allSatisfy {
            LSSharedFileListItemRemove(list, $0) == noErr
        }
    }

    private static func loginItem(at path: String) -> LSSharedFileListItem? {
        return snapshot?.items.first { item in
            guard let url = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() else {
                return false
            }
            return URL(fileURLWithPath: path).absoluteString == (url as URL).absoluteString
        }
    }
}
