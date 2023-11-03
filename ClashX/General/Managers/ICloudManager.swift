//
//  ICloudManager.swift
//  ClashX
//
//  Created by yicheng on 2020/5/10.
//  Copyright © 2020 west2online. All rights reserved.
//

import Cocoa
import RxCocoa
import RxSwift

class ICloudManager {
    static let shared = ICloudManager()
    private let queue = DispatchQueue(label: "com.clashx.icloud")
    private var metaQuery: NSMetadataQuery?
    private var enableMenuItem: NSMenuItem?
    private(set) var icloudAvailable = false {
        didSet { useiCloud.accept(userEnableiCloud && icloudAvailable) }
    }

    private var disposeBag = DisposeBag()

    let useiCloud = BehaviorRelay<Bool>(value: false)

    var userEnableiCloud: Bool = UserDefaults.standard.bool(forKey: "kUserEnableiCloud") {
        didSet {
            UserDefaults.standard.set(userEnableiCloud, forKey: "kUserEnableiCloud")
            useiCloud.accept(userEnableiCloud && icloudAvailable)
        }
    }

    func setup() {
        addNotification()
        useiCloud.distinctUntilChanged().filter { $0 }.subscribe {
            [weak self] _ in
            self?.checkiCloud()
        }.disposed(by: disposeBag)

        icloudAvailable = isICloudAvailable()
        useiCloud.accept(userEnableiCloud && icloudAvailable)
    }

    func getConfigFilesList(configs: @escaping (([String]) -> Void)) {
        getUrl { url in
            guard let url = url,
                  let fileURLs = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                configs([])
                return
            }
            let list = fileURLs
                .filter { String($0.split(separator: ".").last ?? "") == "yaml" }
                .map { $0.split(separator: ".").dropLast().joined(separator: ".") }
            configs(list)
        }
    }

    private func checkiCloud() {
        getUrl { url in
            guard let url = url else {
                self.icloudAvailable = false
                return
            }
            let files = try? FileManager.default.contentsOfDirectory(atPath: url.path)
            if files?.isEmpty == true {
                let path = Bundle.main.path(forResource: "sampleConfig", ofType: "yaml")!
                try? FileManager.default.copyItem(atPath: path, toPath: kDefaultConfigFilePath)
                try? FileManager.default.copyItem(atPath: Bundle.main.path(forResource: "sampleConfig", ofType: "yaml")!, toPath: url.appendingPathComponent("config.yaml").path)
            }
        }
    }

    private func isICloudAvailable() -> Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    func getUrl(complete: ((URL?) -> Void)? = nil) {
        queue.async {
            guard var url = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                DispatchQueue.main.async {
                    complete?(nil)
                }
                return
            }
            url.appendPathComponent("Documents")
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)
                }
                DispatchQueue.main.async {
                    complete?(url)
                }
            } catch let err {
                Logger.log("\(err)")
                DispatchQueue.main.async {
                    complete?(nil)
                }
                return
            }
        }
    }

    private func addNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(iCloudAccountAvailabilityChanged), name: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil)
    }

    @objc func iCloudAccountAvailabilityChanged() {
        icloudAvailable = isICloudAvailable()
    }
}
