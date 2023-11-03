//
//  NSTableView+Reload.swift
//  ClashX
//
//  Created by yicheng on 2019/7/28.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

extension NSTableView {
    func reloadDataKeepingSelection() {
        let selectedRowIndexes = selectedRowIndexes
        reloadData()
        var indexs = IndexSet()
        for index in selectedRowIndexes {
            if index >= 0 && index <= numberOfRows {
                indexs.insert(index)
            }
        }
        selectRowIndexes(indexs, byExtendingSelection: false)
    }
}
