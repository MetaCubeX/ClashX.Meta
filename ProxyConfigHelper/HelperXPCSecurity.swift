//
//  HelperXPCSecurity.swift
//  com.metacubex.ClashX.ProxyConfigHelper
//

import Foundation
import Security
import os.log

enum HelperXPCSecurity {
	// Ad-hoc releases are validated by their signing identifier.
	private static let clientCodeSigningRequirement = #"identifier "com.metacubex.ClashX.meta""#

	private struct RequirementState {
		let requirement: SecRequirement?
		let status: OSStatus
	}

	private static let requirementState: RequirementState = {
		var requirement: SecRequirement?
		let status = SecRequirementCreateWithString(
			clientCodeSigningRequirement as CFString,
			[],
			&requirement
		)
		return RequirementState(requirement: requirement, status: status)
	}()

	static func isValid(processIdentifier: pid_t) -> Bool {
		// NSRunningApplication.bundleIdentifier can be unavailable when inspected
		// from a root launch daemon. Resolve the live process through Security.framework.
		let attributes = [
			kSecGuestAttributePid as String: NSNumber(value: processIdentifier)
		] as CFDictionary

		var guestCode: SecCode?
		let resolveStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode)
		guard resolveStatus == errSecSuccess,
		      let guestCode else {
			os_log(
				"Rejecting XPC client: unable to resolve code for pid %{public}d (OSStatus %{public}d)",
				type: .error,
				processIdentifier,
				resolveStatus
			)
			return false
		}

		guard requirementState.status == errSecSuccess,
		      let requirement = requirementState.requirement else {
			os_log(
				"Rejecting XPC client: unable to create its code-signing requirement (OSStatus %{public}d)",
				type: .error,
				requirementState.status
			)
			return false
		}

		let validationStatus = SecCodeCheckValidity(
			guestCode,
			SecCSFlags(rawValue: kSecCSStrictValidate),
			requirement
		)
		guard validationStatus == errSecSuccess else {
			os_log(
				"Rejecting XPC client: invalid ClashX Meta code signature (OSStatus %{public}d)",
				type: .error,
				validationStatus
			)
			return false
		}

		return true
	}
}
