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

	subscript (index: Int) -> String {
		return self[index ..< index + 1]
	}

	func substring(fromIndex: Int) -> String {
		return self[min(fromIndex, length) ..< length]
	}

	func substring(toIndex: Int) -> String {
		return self[0 ..< max(0, toIndex)]
	}

	subscript (range: Range<Int>) -> String {
		let newRange = Range(uncheckedBounds: (lower: max(0, min(length, range.lowerBound)),
											upper: min(length, max(0, range.upperBound))))
		let start = index(startIndex, offsetBy: newRange.lowerBound)
		let end = index(start, offsetBy: newRange.upperBound - newRange.lowerBound)
		return String(self[start ..< end])
	}
}
