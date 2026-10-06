//
//  LogsTableView.swift
//  
//
//

import Cocoa
import SwiftUI

struct LogsTableView<Item: Hashable>: NSViewRepresentable {
	
	enum TableColumn: String, CaseIterable {
		case date = "Date"
		case level = "Level"
		case log = "Log"
	}
	
	var data: [Item]
	var filterString: String
	var logFilter: DashboardToolbarState.LogFilter
	
	class NonRespondingScrollView: NSScrollView {
		override var acceptsFirstResponder: Bool { false }
	}

	class NonRespondingTableView: NSTableView {
		override var acceptsFirstResponder: Bool { false }
	}

	func makeNSView(context: Context) -> NSScrollView {
		
		let scrollView = NonRespondingScrollView()
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true

		let tableView = NonRespondingTableView()
		tableView.usesAlternatingRowBackgroundColors = true
		
		tableView.delegate = context.coordinator
		tableView.dataSource = context.coordinator
		
		TableColumn.allCases.forEach {
			let tableColumn = NSTableColumn(identifier: .init("LogsTableView." + $0.rawValue))
			tableColumn.title = NSLocalizedString($0.rawValue, comment: "")
			tableColumn.isEditable = false
			
			switch $0 {
			case .date:
				tableColumn.minWidth = 60
				tableColumn.maxWidth = 140
				tableColumn.width = 135
			case .level:
				tableColumn.minWidth = 40
				tableColumn.maxWidth = 65
			default:
				tableColumn.minWidth = 120
				tableColumn.maxWidth = .infinity
			}
			
			tableView.addTableColumn(tableColumn)
		}
		
		scrollView.documentView = tableView

		return scrollView
	}
	
	func updateNSView(_ nsView: NSScrollView, context: Context) {
		context.coordinator.parent = self
		guard let tableView = nsView.documentView as? NSTableView,
			  var data = data as? [ClashLogStorage.ClashLog] else {
			return
		}
		data = updateSorts(data, tableView: tableView)
		context.coordinator.updateLogs(data, for: tableView)
	}
	
	func updateSorts(_ objects: [ClashLogStorage.ClashLog],
					 tableView: NSTableView) -> [ClashLogStorage.ClashLog] {
		var re = objects
		
		let filterKeys = [
			"levelString",
			"log",
		]
		
        switch logFilter {
        case .all:
            break
        case .rule:
            re = re.filter {
                $0.log.starts(with: "[Rule")
                || $0.log.starts(with: "[TCP")
                || $0.log.starts(with: "[UDP")
            }
        case .dns:
            re = re.filter {
                $0.log.starts(with: "[DNS")
            }
        case .others:
            re = re.filter {
                !$0.log.starts(with: "[DNS")
                && !$0.log.starts(with: "[Rule")
                && !$0.log.starts(with: "[TCP")
                && !$0.log.starts(with: "[UDP")
            }
        }
        
        
		re = re.filtered(filterString, for: filterKeys)
		
		return re
	}
	
	
	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}
	
	
	class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {

		var parent: LogsTableView
		var logs = [ClashLogStorage.ClashLog]()
		
		let dateFormatter = {
			let df = DateFormatter()
			df.dateFormat = "MM/dd HH:mm:ss.SSS"
			return df
		}()
		
		init(parent: LogsTableView) {
			self.parent = parent
		}
		
		func updateLogs(_ logs: [ClashLogStorage.ClashLog], for tableView: NSTableView) {
			
			let changes = logs.difference(from: self.logs) {
				$0.id == $1.id
			}
			
			guard let partialChanges = self.logs.applying(changes) else { return }
			
			self.logs = partialChanges

			let indicesToReload = IndexSet(zip(partialChanges, logs).enumerated().compactMap { index, pair -> Int? in
				(pair.0.id == pair.1.id && pair.0 != pair.1) ? index : nil
			})
			
			tableView.reloadData(changes, indexs: indicesToReload)
		}
		
		
		func numberOfRows(in tableView: NSTableView) -> Int {
			logs.count
		}

		
		func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
			
			guard let identifier = tableColumn?.identifier,
				  let cellView = tableView.makeCellView(with: identifier.rawValue, owner: self),
				  let s = identifier.rawValue.split(separator: ".").last,
				  let tc = TableColumn(rawValue: String(s)),
				  row >= 0,
				  row < logs.count,
				  let tf = cellView.textField
			else { return nil }
			
			let log = logs[row]
			
			tf.isEditable = false
			tf.isSelectable = false
			
			switch tc {
			case .date:
				tf.lineBreakMode = .byTruncatingHead
				tf.textColor = .orange
				tf.stringValue = dateFormatter.string(from: log.date)
			case .level:
				tf.lineBreakMode = .byTruncatingTail
				tf.textColor = log.levelColor
				tf.stringValue = log.levelString
			case .log:
				tf.lineBreakMode = .byTruncatingTail
				tf.textColor = .labelColor
				tf.stringValue = log.log
				tf.isSelectable = true
			}
			
			return cellView
		}
	}
}
