//
//  DateFormatter+.swift
//  ClashX
//
//  Created by yicheng on 2019/12/14.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

extension DateFormatter {
    static let js: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: NSCalendar.Identifier.ISO8601.rawValue)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SZ"
        return f
    }()

    static let simple: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static let provider: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSZZ"
        return f
    }()
}
