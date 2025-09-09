//
//  Url.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 5/5/23.
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
	
	/// A subscript that retrieves the value of a specific query parameter from the URL.
	subscript(queryParam: String) -> String? {
		guard let url = URLComponents(string: self.absoluteString) else { return nil }
		return url.queryItems?.first(where: { $0.name == queryParam })?.value
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
