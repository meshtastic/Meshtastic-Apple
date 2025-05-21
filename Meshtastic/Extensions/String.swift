//
//  String.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation
import UIKit

extension String {

	func base64urlToBase64() -> String {
		var base64 = self
			.replacingOccurrences(of: "-", with: "+")
			.replacingOccurrences(of: "_", with: "/")
		if base64.count % 4 != 0 {
			base64.append(String(repeating: "==", count: 4 - base64.count % 4))
		}
		return base64
	}

	func base64ToBase64url() -> String {
		let base64url = self
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
		return base64url
	}

	var localized: String { NSLocalizedString(self, comment: self) }
	func isEmoji() -> Bool {
		// Emoji are no more than 4 bytes
		if self.count > 4 {
			return false
		} else {
			let characters = Array(self)
			if characters.count <= 0 {
				return false
			} else {
				return characters[0].isEmoji
			}
		}
	}
	func onlyEmojis() -> Bool {
		return count > 0 && !contains { !$0.isEmoji }
	}

	func image(fontSize: CGFloat = 40, bgColor: UIColor = UIColor.clear, imageSize: CGSize? = nil) -> UIImage? {
		let font = UIFont.systemFont(ofSize: fontSize)
		let attributes = [NSAttributedString.Key.font: font]
		let imageSize = imageSize ?? self.size(withAttributes: attributes)
		UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
		bgColor.set()
		let rect = CGRect(origin: .zero, size: imageSize)
		UIRectFill(rect)
		self.draw(in: rect, withAttributes: [.font: font])
		let image = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		return image
	}

	func camelCaseToWords() -> String {
		return self
			.replacingOccurrences(of: "([a-z])([A-Z](?=[A-Z])[a-z]*)", with: "$1 $2", options: .regularExpression)
			.replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
			.replacingOccurrences(of: "([a-z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
	}

	var length: Int {
		return count
	}

	subscript (i: Int) -> String {
		return self[i ..< i + 1]
	}

	func substring(fromIndex: Int) -> String {
		return self[min(fromIndex, length) ..< length]
	}

	func substring(toIndex: Int) -> String {
		return self[0 ..< max(0, toIndex)]
	}

	subscript (r: Range<Int>) -> String {
		let range = Range(uncheckedBounds: (lower: max(0, min(length, r.lowerBound)),
											upper: min(length, max(0, r.upperBound))))
		let start = index(startIndex, offsetBy: range.lowerBound)
		let end = index(start, offsetBy: range.upperBound - range.lowerBound)
		return String(self[start ..< end])
	}

	// Filter out variation selectors from the string
	var withoutVariationSelectors: String {
		var scalars: [UnicodeScalar] = []
		var previousWasASCII = false

		for scalar in self.unicodeScalars {
			if scalar.properties.isVariationSelector {
				// Only keep variation selector if the previous character was ASCII
				if previousWasASCII {
					scalars.append(scalar)
				}
				// No need to update previousWasASCII since variation selectors aren't characters
				// Shouldn't have 2 in a row
			} else {
				scalars.append(scalar)
				previousWasASCII = scalar.isASCII
			}
		}

		return scalars.compactMap { UnicodeScalar($0) }
			.map { String($0) }
			.joined()
	}

	/// Formats a short name like "P130" to read as "Node P 130" for VoiceOver
	/// This ensures proper pronunciation of alphanumeric node IDs
	func formatNodeNameForVoiceOver() -> String {
		let spaced = self.replacingOccurrences(
			of: #"([A-Za-z])([0-9]+)"#,
			with: "$1 $2",
			options: .regularExpression
		)
		return "Node " + spaced
	}

	// Adds variation selectors to prefer the graphical form of emoji.
	// Looks ahead to make sure that the variation selector is not already applied.
	var addingVariationSelectors: String {
		var result = ""
		let scalars = self.unicodeScalars
		var index = scalars.startIndex
		while index < scalars.endIndex {
			let currentScalar = scalars[index]
			result += String(currentScalar)
			if currentScalar.properties.isEmoji && !currentScalar.properties.isEmojiPresentation && !currentScalar.isASCII {
				// Check if the next scalar is U+FE0F
				let nextIndex = scalars.index(after: index)
				if nextIndex < scalars.endIndex && scalars[nextIndex].value == 0xFE0F {
					// Already has variation selector; skip the next scalar
					index = nextIndex
				} else {
					// Append variation selector
					result += String(UnicodeScalar(0xFE0F)!)
				}
			}
			// Move to the next scalar
			index = scalars.index(after: index)
		}
		return result
	}
}
