//
//  MetaPrefsViewController.swift
//  ClashX Meta
//
//  Copyright © 2023 west2online. All rights reserved.
//

import Cocoa
import Network

class MetaPrefsViewController: NSViewController {
	// Meta Setting
	@IBOutlet var hideUnselectableButton: NSButton!
	
	@IBAction func hideUnselectable(_ sender: NSButton) {
		var newState = NSControl.StateValue.off
		switch sender.state {
		case .off:
			newState = .mixed
		case .mixed:
			newState = .on
		case .on:
			newState = .off
		default:
			return
		}

		sender.state = newState
		MenuItemFactory.hideUnselectable = newState.rawValue
	}
	
	@IBOutlet var tunDNSTextField: NSTextField!
	@IBAction func tunDNSChanged(_ sender: NSTextField) {
		let ds = sender.stringValue
		guard let _ = IPv4Address(ds) else { return }
		ConfigManager.metaTunDNS = ds
		updateNeedsRestart()
	}
	
	// Dashboard
	@IBOutlet var useSwiftuiButton: NSButton!
	@IBOutlet var useYacdButton: NSButton!
	@IBOutlet var useXDButton: NSButton!
    @IBOutlet var useZashButton: NSButton!
    
    
    @IBAction func switchDashboard(_ sender: NSButton) {
		switch sender {
		case useSwiftuiButton:
			DashboardManager.shared.useSwiftUI = sender.state == .on
		case useYacdButton:
            ConfigManager.webDashboard = .yacd
		case useXDButton:
            ConfigManager.webDashboard = .metacubexd
        case useZashButton:
            ConfigManager.webDashboard = .zashboard
		default:
			break
		}
		initDashboardButtons()
		updateNeedsRestart()
	}
	
	// Alpha Core
	@IBOutlet var useAlphaButton: NSButton!
	@IBOutlet var alphaVersionTextField: NSTextField!
	@IBOutlet var updateButton: NSButton!
	@IBOutlet var updateProgressIndicator: NSProgressIndicator!
	@IBOutlet var showAlphaButton: NSButton!
	

	@IBAction func useAlphaMeta(_ sender: NSButton) {
		if UserDefaults.standard.object(forKey: "useAlphaCore") as? Bool == nil {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("Alpha Meta core Warning", comment: "")
			alert.alertStyle = .warning
			alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
			alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
			if alert.runModal() != .alertFirstButtonReturn {
				return
			}
		}

		let use = sender.state == .on
		ConfigManager.useAlphaCore = use
		updateNeedsRestart()
	}
	
	@IBAction func updateAlpha(_ sender: NSButton) {
        alphaInfoGeneration += 1
		sender.isEnabled = false
		updateProgressIndicator.isHidden = false
		updateProgressIndicator.startAnimation(nil)
		
		let dl = AlphaMetaDownloader.self
		
		Task {
			do {
                let info = try await dl.update()
                let newVer = info.version

				await MainActor.run {
					self.updateAlphaVersion(newVer)
					let msg = NSLocalizedString("Version: ", comment: "") + newVer
					UserNotificationCenter.shared.postNotificationAlert(title: "Clash Meta Core", info: msg)
				}
			} catch {
                await MainActor.run {
                    UserNotificationCenter.shared.postNotificationAlert(title: "Clash Meta Core", info: error.localizedDescription)
                    self.setAlphaVersion()
                }
			}
			
			await MainActor.run {
				sender.isEnabled = true
				self.updateProgressIndicator.isHidden = true
				self.updateProgressIndicator.stopAnimation(nil)
			}
		}
	}
	
	@IBAction func showAlphaInFinder(_ sender: NSButton) {
		guard let u = Paths.alphaCorePath(),
			  FileManager.default.fileExists(atPath: u.path) else { return }
		NSWorkspace.shared.activateFileViewerSelecting([u])
	}
	
	
	@IBOutlet var restartTextField: NSTextField!
	
	var prefsSnapshot = [String]()
	var versionSnapshot = "none"
	var alphaCoreUpdated = false
    private var alphaInfoGeneration = 0
	
	override func viewDidLoad() {
        super.viewDidLoad()
		// Meta Setting
		hideUnselectableButton.state = .init(rawValue: MenuItemFactory.hideUnselectable)
		
		tunDNSTextField.placeholderString = ConfigManager.defaultTunDNS
		tunDNSTextField.stringValue = ConfigManager.metaTunDNS
		tunDNSTextField.delegate = self
		
		// Dashboard
		initDashboardButtons()
		
		// Alpha Core
		useAlphaButton.state = ConfigManager.useAlphaCore ? .on : .off
		updateProgressIndicator.isHidden = true
		setAlphaVersion()
		
		// Snapshot
		prefsSnapshot = takePrefsSnapshot()
		versionSnapshot = alphaVersionTextField.stringValue
		restartTextField.isHidden = true
    }
	
	func initDashboardButtons() {
		let useSwiftUI = DashboardManager.shared.useSwiftUI
		let dashboard = ConfigManager.webDashboard
		
        useSwiftuiButton.isEnabled = true
		useSwiftuiButton.state = useSwiftUI ? .on : .off
        
        let buttons = [useYacdButton, useXDButton, useZashButton]
        
        buttons.forEach {
            $0?.state = .off
            $0?.isEnabled = !useSwiftUI
        }
        
        switch dashboard {
        case .yacd:
            useYacdButton.state = .on
        case .metacubexd:
            useXDButton.state = .on
        case .zashboard:
            useZashButton.state = .on
        }
	}
	
    func setAlphaVersion() {
        alphaInfoGeneration += 1
        let generation = alphaInfoGeneration
        Task {
            let info = try? await AlphaMetaDownloader.installed()
            await MainActor.run {
                guard generation == self.alphaInfoGeneration else { return }
                self.versionSnapshot = info?.version ?? "none"
                self.updateAlphaVersion(info?.version)
            }
        }
    }

	func updateAlphaVersion(_ version: String?) {
		let enable = version != nil
		useAlphaButton.isEnabled = enable || ConfigManager.useAlphaCore
		showAlphaButton.isEnabled = enable
		if let v = version {
			alphaVersionTextField.stringValue = v
			updateButton.title = NSLocalizedString("Update Alpha Meta core", comment: "")
		} else {
			alphaVersionTextField.stringValue = "none"
			updateButton.title = NSLocalizedString("Download Meta core", comment: "")
		}
		
		if let v = version,
		   versionSnapshot != "none",
		   v != versionSnapshot {
			alphaCoreUpdated = true
			updateNeedsRestart()
		}
	}
	
	func takePrefsSnapshot() -> [String] {
		[
			ConfigManager.metaTunDNS,
            ConfigManager.webDashboard.rawValue,
			"\(ConfigManager.useAlphaCore)"
		]
	}
	
	func updateNeedsRestart() {
		let needsRestart = prefsSnapshot != takePrefsSnapshot() || alphaCoreUpdated
		restartTextField.isHidden = !needsRestart
	}
}

extension MetaPrefsViewController: NSTextFieldDelegate {
	func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
		IPv4Address(fieldEditor.string) != nil
	}
}
