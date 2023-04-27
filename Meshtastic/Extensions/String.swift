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
		return unicodeScalars.dropFirst().reduce(String(prefix(1))) {
			return CharacterSet.uppercaseLetters.contains($1)
				? $0 + " " + String($1)
				: $0 + String($1)
		}
	}
}
