//
//  NetworkStatusCardView.swift
//  ClashX Dashboard
//
//

import AppKit
import SwiftUI

// System proxy, TUN, and HTTP proxy status; copies terminal proxy commands
struct NetworkStatusCardView: View {
	@EnvironmentObject private var poller: NetworkStatusPoller
	@State private var copied = false
	@State private var apiCopied = false
	// Reset handles so a re-click cancels the pending reset of the previous one.
	@State private var copiedResetTask: Task<Void, Never>?
	@State private var apiCopiedResetTask: Task<Void, Never>?

	private let rowHeight: CGFloat = 24
	private let valueFont = Font.system(size: 16)

	var body: some View {
		OverviewCard {
			VStack(alignment: .leading, spacing: DashboardTheme.spacingRowInner) {
				Text("Network")
					.font(DashboardTheme.titleFont)
			infoRow(label: "Sys Proxy") {
				systemProxyValue
			}
			infoRow(label: "TUN",
					value: poller.tunActive ? poller.tunDevice : "Off",
					valueColor: poller.tunActive ? nil : .secondary)
				httpRow
				apiRow
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		}
	}

	private func infoRow(label: LocalizedStringKey, value: String, valueColor: Color? = nil) -> some View {
		infoRow(label: label, valueColor: valueColor) {
			Text(verbatim: value)
				.font(valueFont)
				.foregroundColor(valueColor ?? .primary)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
		}
	}

	private func infoRow(label: LocalizedStringKey, valueColor: Color? = nil, @ViewBuilder value: () -> some View) -> some View {
		HStack(spacing: DashboardTheme.spacingRowInner) {
			Text(label)
				.font(DashboardTheme.overviewLabelFont)
				.foregroundColor(.secondary)
				.frame(width: 90, alignment: .leading)
			value()
				.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(height: rowHeight)
	}

	@ViewBuilder
	private var systemProxyValue: some View {
		CheckboxView(state: systemProxyCheckboxState)
			.allowsHitTesting(false)
	}

	private var systemProxyCheckboxState: NSControl.StateValue {
		if poller.systemProxySetByOther { return .mixed }
		return poller.systemProxyActive ? .on : .off
	}

	private var httpRow: some View {
		HStack(spacing: DashboardTheme.spacingRowInner) {
			Text("HTTP(S)")
				.font(DashboardTheme.overviewLabelFont)
				.foregroundColor(.secondary)
				.frame(width: 90, alignment: .leading)
			Text(verbatim: poller.httpPort > 0 ? "\(poller.httpPort)" : "—")
				.font(valueFont)
				.monospacedDigit()
				.lineLimit(1)
			Spacer()
			copyButton(isCopied: copied) {
				copyProxyCommand()
			}
			.help("Copy terminal proxy command")
		}
		.frame(height: rowHeight)
	}

	private var apiRow: some View {
		HStack(spacing: DashboardTheme.spacingRowInner) {
			Text("API")
				.font(DashboardTheme.overviewLabelFont)
				.foregroundColor(.secondary)
				.frame(width: 90, alignment: .leading)
			Text(verbatim: poller.apiAddress)
				.font(valueFont)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
			Spacer()
			copyButton(isCopied: apiCopied) {
				copyAPILink()
			}
			.help("Copy API address")
		}
		.frame(height: rowHeight)
	}

	private func copyButton(isCopied: Bool, action: @escaping () -> Void) -> some View {
		Button {
			action()
		} label: {
			Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
				.font(.system(size: 13))
				.foregroundColor(isCopied ? .green : .secondary)
		}
		.buttonStyle(.plain)
		.contentShape(Rectangle())
	}

	private func copyAPILink() {
		guard poller.apiAddress != "—" else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(poller.apiAddress, forType: .string)
		apiCopiedResetTask?.cancel()
		apiCopied = true
		apiCopiedResetTask = Task {
			try? await Task.sleep(seconds: 1.2)
			guard !Task.isCancelled else { return }
			apiCopied = false
		}
	}

	private func copyProxyCommand() {
		guard poller.httpPort > 0 else { return }
		let base = "http://127.0.0.1:\(poller.httpPort)"
		var parts = ["export https_proxy=\(base)", "http_proxy=\(base)"]
		if poller.socksPort > 0 {
			parts.append("all_proxy=socks5://127.0.0.1:\(poller.socksPort)")
		}
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(parts.joined(separator: " "), forType: .string)
		copiedResetTask?.cancel()
		copied = true
		copiedResetTask = Task {
			try? await Task.sleep(seconds: 1.2)
			guard !Task.isCancelled else { return }
			copied = false
		}
	}
}

private struct CheckboxView: NSViewRepresentable {
	let state: NSControl.StateValue

	func makeNSView(context: Context) -> NSButton {
		NSButton(checkboxWithTitle: "", target: nil, action: nil)
	}

	func updateNSView(_ checkbox: NSButton, context: Context) {
		checkbox.state = state
	}
}
