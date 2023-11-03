//
//  SpeedUtils.swift
//  ClashX
//
//  Created by yicheng on 2023/7/6.
//  Copyright © 2023 west2online. All rights reserved.
//

import Foundation

enum SpeedUtils {
    static func getSpeedString(for byte: Int) -> String {
        return getNetString(for: byte).appending("/s")
    }

    static func getNetString(for byte: Int) -> String {
        let kb = byte / 1024
        if kb < 1024 {
            return "\(kb)KB"
        } else {
            let mb = Double(kb) / 1024.0
            if mb >= 100 {
                if mb >= 1000 {
                    return String(format: "%.1fGB", mb / 1024)
                }
                return String(format: "%.1fMB", mb)
            } else {
                return String(format: "%.2fMB", mb)
            }
        }
    }
}
