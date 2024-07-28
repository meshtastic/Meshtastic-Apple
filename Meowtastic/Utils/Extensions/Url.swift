//
//  Url.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 5/5/23.
//

import Foundation
import OSLog

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
	var attributes: [FileAttributeKey: Any]? {
		do {
			return try FileManager.default.attributesOfItem(atPath: path)
		} catch let error as NSError {
			Logger.services.error("FileAttribute error: \(error, privacy: . public)")
		}
		return nil
	}

	var fileSize: UInt64 {
		return attributes?[.size] as? UInt64 ?? UInt64(0)
	}

	var fileSizeString: String {
		return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
	}

	var creationDate: Date? {
		return attributes?[.creationDate] as? Date
	}
}
