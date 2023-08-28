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
}
