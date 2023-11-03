//
//  NSView+Nib.swift
//  ClashX
//
//  Created by yicheng on 2019/7/28.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

protocol NibLoadable {
    static var nibName: String? { get }
    static func createFromNib(in bundle: Bundle) -> Self
}

extension NibLoadable where Self: NSView {
    static var nibName: String? {
        return String(describing: Self.self)
    }

    static func createFromNib(in bundle: Bundle = Bundle.main) -> Self {
        guard let nibName = nibName else { fatalError() }
        var topLevelArray: NSArray?
        bundle.loadNibNamed(NSNib.Name(nibName), owner: self, topLevelObjects: &topLevelArray)
        guard let results = topLevelArray else { fatalError() }
        let views = [Any](results).filter { $0 is Self }
        return views.last as! Self
    }
}

extension NibLoadable where Self: NSViewController {
    static var nibName: String? {
        return String(describing: Self.self)
    }

    static func createFromNib(in bundle: Bundle = Bundle.main) -> Self {
        guard let nibName = nibName else { fatalError() }
        let sb = NSStoryboard(name: "Main", bundle: Bundle.main)
        return sb.instantiateController(withIdentifier: nibName) as! Self
    }
}
