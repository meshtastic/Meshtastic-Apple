//
//  Url.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 5/5/23.
//

import Foundation

extension URL {
	
	func regularFileAllocatedSize() throws -> UInt64 {
		let resourceValues = try self.resourceValues(forKeys: allocatedSizeResourceKeys)
		
		guard resourceValues.isRegularFile ?? false else {
			return 0
		}
		return UInt64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
	}
	subscript(queryParam: String) -> String? {
		guard let url = URLComponents(string: self.absoluteString) else { return nil }
		if let parameters = url.queryItems {
			return parameters.first(where: { $0.name == queryParam })?.value
		} else if let paramPairs = url.fragment?.components(separatedBy: "?").last?.components(separatedBy: "&") {
			for pair in paramPairs where pair.contains(queryParam) {
				return pair.components(separatedBy: "=").last
			}
			return nil
		} else {
			return nil
		}
	}
}
