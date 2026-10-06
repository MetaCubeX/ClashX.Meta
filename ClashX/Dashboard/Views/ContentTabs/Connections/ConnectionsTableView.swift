//
//  ConnectionsTableView.swift
//  ClashX Dashboard
//
//
import SwiftUI
import AppKit

struct ConnectionsTableView<Item: Hashable>: NSViewRepresentable {

	enum TableColumn: String, CaseIterable {
		case host = "Host"
		case sniffHost = "Sniff Host"
		case process = "Process"
		case dlSpeed = "DL Speed"
		case ulSpeed = "UL Speed"
		case dl = "DL"
		case ul = "UL"
		case chain = "Chain"
		case rule = "Rule"
		case time = "Time"
		case source = "Source"
		case destinationIP = "Destination IP"
		case type = "Connection Type"
	}
	
	
	var data: [Item]

	class NonRespondingScrollView: NSScrollView {
		override var acceptsFirstResponder: Bool { false }
	}

	class NonRespondingTableView: NSTableView {
		override var acceptsFirstResponder: Bool { false }
	}

	func makeNSView(context: Context) -> NSScrollView {
		
		let scrollView = NonRespondingScrollView()
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true

		let tableView = NonRespondingTableView()
		tableView.usesAlternatingRowBackgroundColors = true
		
		tableView.delegate = context.coordinator
		tableView.dataSource = context.coordinator
		
		let menu = NSMenu()
		menu.showsStateColumn = true
		tableView.headerView?.menu = menu
		
		
		TableColumn.allCases.forEach {
			let tableColumn = NSTableColumn(identifier: .init("ConnectionsTableView." + $0.rawValue))
			tableColumn.title = NSLocalizedString($0.rawValue, comment: "")
			tableColumn.isEditable = false
			
			tableColumn.minWidth = 50
			tableColumn.maxWidth = .infinity
			
			
			tableView.addTableColumn(tableColumn)
			
			var sort: NSSortDescriptor?
			
			switch $0 {
			case .host:
				sort = .init(keyPath: \DBConnectionObject.host, ascending: true)
			case .sniffHost:
				sort = .init(keyPath: \DBConnectionObject.sniffHost, ascending: true)
			case .process:
				sort = .init(keyPath: \DBConnectionObject.process, ascending: true)
			case .dlSpeed:
				sort = .init(keyPath: \DBConnectionObject.downloadSpeed, ascending: true)
			case .ulSpeed:
				sort = .init(keyPath: \DBConnectionObject.uploadSpeed, ascending: true)
			case .dl:
				sort = .init(keyPath: \DBConnectionObject.download, ascending: true)
			case .ul:
				sort = .init(keyPath: \DBConnectionObject.upload, ascending: true)
			case .chain:
				sort = .init(keyPath: \DBConnectionObject.chainString, ascending: true)
			case .rule:
				sort = .init(keyPath: \DBConnectionObject.ruleString, ascending: true)
			case .time:
				sort = .init(keyPath: \DBConnectionObject.startDate, ascending: true)
			case .source:
				sort = .init(keyPath: \DBConnectionObject.source, ascending: true)
			case .destinationIP:
				sort = .init(keyPath: \DBConnectionObject.destinationIP, ascending: true)
			case .type:
				sort = .init(keyPath: \DBConnectionObject.type, ascending: true)
			}
			
			tableColumn.sortDescriptorPrototype = sort
			
			let item = NSMenuItem(
				title: NSLocalizedString($0.rawValue, comment: ""),
				action: #selector(context.coordinator.toggleColumn(_:)),
				keyEquivalent: "")
			item.target = context.coordinator
			item.representedObject = tableColumn
			
			menu.addItem(item)
		}
		
		
		if let sort = tableView.tableColumns.first?.sortDescriptorPrototype {
			tableView.sortDescriptors = [sort]
		}
		
		
		scrollView.documentView = tableView

		tableView.autosaveName = "ClashX_Dashboard.Connections.TableView"
		tableView.autosaveTableColumns = true
		
		menu.items.forEach {
			guard let column = $0.representedObject as? NSTableColumn else { return }
			$0.state = column.isHidden ? .off : .on
		}
		
		return scrollView
	}

	func updateNSView(_ nsView: NSScrollView, context: Context) {
		context.coordinator.parent = self
		guard let tableView = nsView.documentView as? NSTableView,
			  let data = data as? [DBConnection] else {
			return
		}
		
		var conns = data.map(DBConnectionObject.init)
		
		let connHistorys = context.coordinator.connHistorys
		conns.forEach {
			$0.updateSpeeds(connHistorys[$0.id])
		}
		
		conns = updateSorts(conns, tableView: tableView)
		context.coordinator.updateConns(conns, for: tableView)
	}
	
	func updateSorts(_ objects: [DBConnectionObject],
					 tableView: NSTableView) -> [DBConnectionObject] {
		var re = objects

		var sortDescriptors = [NSSortDescriptor]()

		if let sort = tableView.sortDescriptors.first {
			sortDescriptors.append(sort)
		}

		sortDescriptors.append(.init(keyPath: \DBConnectionObject.id, ascending: true))
		re = re.sorted(descriptors: sortDescriptors)

		return re
	}
	

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}
	
	class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {

		var parent: ConnectionsTableView
		
		var conns = [DBConnectionObject]()
		var connHistorys = [String: (download: Int64, upload: Int64)]()

		init(parent: ConnectionsTableView) {
			self.parent = parent
		}
		
		func updateConns(_ conns: [DBConnectionObject], for tableView: NSTableView) {
			let changes = conns.difference(from: self.conns) {
				$0.id == $1.id
			}
			
			for change in changes {
				switch change {
				case .remove(_, let conn, _):
					connHistorys[conn.id] = nil
				default:
					break
				}
			}
			conns.forEach {
				connHistorys[$0.id] = ($0.download, $0.upload)
			}
			
			let selectedID: String? = {
				let selectedRow = tableView.selectedRow
				guard selectedRow >= 0, selectedRow < self.conns.count else {
					return nil
				}
				return self.conns[selectedRow].id
			}()
			
			
			guard let partialChanges = self.conns.applying(changes) else {
				return
			}
			self.conns = conns

			let indicesToReload = IndexSet(zip(partialChanges, conns).enumerated().compactMap { index, pair -> Int? in
				(pair.0.id == pair.1.id && pair.0 != pair.1) ? index : nil
			})
			
			tableView.reloadData(changes, indexs: indicesToReload)
			
			if let index = self.conns.firstIndex(where: { $0.id == selectedID }) {
				tableView.selectRowIndexes(.init(integer: index), byExtendingSelection: true)
			}
		}
		
		
		func numberOfRows(in tableView: NSTableView) -> Int {
			conns.count
		}

		
		func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
			
			guard let identifier = tableColumn?.identifier,
				  let cellView = tableView.makeCellView(with: identifier.rawValue, owner: self),
				  let s = identifier.rawValue.split(separator: ".").last,
				  let tc = TableColumn(rawValue: String(s)),
				  row >= 0,
				  row < conns.count,
				  let tf = cellView.textField
			else { return nil }
			
			let conn = conns[row]
			
			tf.isEditable = false
			tf.isSelectable = true
			tf.objectValue = {
				switch tc {
				case .host:
					return conn.host
				case .sniffHost:
					return conn.sniffHost
				case .process:
					return conn.process
				case .dlSpeed:
					return conn.downloadSpeedString
//					return conn.downloadSpeed
				case .ulSpeed:
					return conn.uploadSpeedString
//					return conn.uploadSpeed
				case .dl:
					return conn.downloadString
				case .ul:
					return conn.uploadString
				case .chain:
					return conn.chainString
				case .rule:
					return conn.ruleString
				case .time:
					return conn.startString
				case .source:
					return conn.source
				case .destinationIP:
					return conn.destinationIP
				case .type:
					return conn.type
				}
			}()
			
			return cellView
		}
		
		func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
			conns = parent.updateSorts(conns, tableView: tableView)
			tableView.reloadData()
		}
		
		@objc func toggleColumn(_ menuItem: NSMenuItem) {
			guard let column = menuItem.representedObject as? NSTableColumn else { return }
			let hide = menuItem.state == .on
			column.isHidden = hide
			menuItem.state = hide ? .off : .on
		}

	}
}
