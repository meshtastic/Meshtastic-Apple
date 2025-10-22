//
//  CommonRegex.swift
//  Meshtastic
//
//  Created by Ben Meadors on 7/2/24.
//

import Foundation

enum CommonRegex {
	struct CoordinateMatch {
		let text: Substring
		let range: Range<String.Index>
	}

	private static let coordsRegex: NSRegularExpression = {
		let pattern = #"lat=\d+\s+long=\d+"#
		return try! NSRegularExpression(pattern: pattern)
	}()

	static func firstCoordinateMatch(in string: String) -> CoordinateMatch? {
		let searchRange = NSRange(string.startIndex..<string.endIndex, in: string)
		guard let match = coordsRegex.firstMatch(in: string, options: [], range: searchRange),
		      let swiftRange = Range(match.range, in: string) else {
			return nil
		}
		return CoordinateMatch(text: string[swiftRange], range: swiftRange)
	}
}
