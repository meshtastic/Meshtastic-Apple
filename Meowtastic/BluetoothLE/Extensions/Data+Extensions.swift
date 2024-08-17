import Foundation

extension Data {
	func hex() -> String? {
		guard count > 0 else {
			return nil
		}

		return map {
			String(format: "%02hhX", $0)
		}
		.joined()
	}
}
