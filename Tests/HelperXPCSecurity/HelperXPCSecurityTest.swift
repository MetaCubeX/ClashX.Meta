import Foundation

@main
private enum HelperXPCSecurityTest {
	static func main() {
		guard CommandLine.arguments.count == 2 else {
			fatalError("Expected accepted or rejected")
		}

		let expected = CommandLine.arguments[1]
		let accepted = HelperXPCSecurity.isValid(processIdentifier: getpid())

		switch (expected, accepted) {
		case ("accepted", true), ("rejected", false):
			print("PASS: connection was \(expected)")
		case ("accepted", false):
			fatalError("Authorized client was rejected")
		case ("rejected", true):
			fatalError("Unauthorized client was accepted")
		default:
			fatalError("Expected accepted or rejected")
		}
	}
}
