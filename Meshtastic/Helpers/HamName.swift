import Foundation

struct HamName: Equatable {
	static let separator = "//"
	static let maxCallSignBytes = 7
	static let maxLongNameBytes = 14

	let callSign: String
	let longName: String

	init(callSign: String, longName: String) {
		self.callSign = callSign
		self.longName = longName
	}

	init(composed: String) {
		guard let separatorRange = composed.range(of: Self.separator) else {
			callSign = composed
			longName = ""
			return
		}

		callSign = String(composed[..<separatorRange.lowerBound])
		longName = String(composed[separatorRange.upperBound...])
	}

	var composed: String {
		longName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? callSign
			: callSign + Self.separator + longName
	}

	static func limitCallSign(_ callSign: String) -> String {
		limit(callSign, toUTF8Bytes: maxCallSignBytes)
	}

	static func limitLongName(_ longName: String) -> String {
		limit(longName, toUTF8Bytes: maxLongNameBytes)
	}

	static func forOnboarding(_ ownerLongName: String) -> String {
		let name = HamName(composed: ownerLongName)
		guard name.callSign.utf8.count > maxCallSignBytes else { return ownerLongName }
		let descriptiveName = name.longName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? name.callSign
			: name.longName
		return HamName(callSign: "", longName: limitLongName(descriptiveName)).composed
	}

	static func forUnlicensing(_ ownerLongName: String) -> String {
		let name = HamName(composed: ownerLongName)
		return name.callSign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name.longName : ownerLongName
	}

	private static func limit(_ value: String, toUTF8Bytes maxBytes: Int) -> String {
		var result = ""
		for character in value {
			guard result.utf8.count + String(character).utf8.count <= maxBytes else { break }
			result.append(character)
		}
		return result
	}
}
