//
//  FileManager.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 5/5/23.
//
import Foundation
import OSLog

let allocatedSizeResourceKeys: Set<URLResourceKey> = [
  .isRegularFileKey,
  .fileAllocatedSizeKey,
  .totalFileAllocatedSizeKey
]

public extension FileManager {

  /// Calculate the allocated size of a directory and all its contents on the volume.
  ///
  /// As there's no simple way to get this information from the file system the method
  /// has to crawl the entire hierarchy, accumulating the overall sum on the way.
  /// The resulting value is roughly equivalent with the amount of bytes
  /// that would become available on the volume if the directory would be deleted.
  ///
  /// - note: There are a couple of oddities that are not taken into account (like symbolic links, meta data of
  /// directories, hard links, ...).
  func allocatedSizeOfDirectory(at directoryURL: URL) -> String {

	// The error handler simply stores the error and stops traversal
	var enumeratorError: Error?
	func errorHandler(_: URL, error: Error) -> Bool {
	  enumeratorError = error
	  return false
	}

	// We have to enumerate all directory contents, including subdirectories.
	let enumerator = self.enumerator(at: directoryURL,
									 includingPropertiesForKeys: Array(allocatedSizeResourceKeys),
									 options: [],
									 errorHandler: errorHandler)!

	// We'll sum up content size here:
	var accumulatedSize: UInt64 = 0

	// Perform the traversal.
	for item in enumerator {

	  // Bail out on errors from the errorHandler.
	  if enumeratorError != nil { break }

	  // Add up individual file sizes.
	  guard let contentItemURL = item as? URL else { continue }
	  do {
		accumulatedSize += try contentItemURL.regularFileAllocatedSize()
	  } catch {
		  Logger.services.error("💥 File Manager Error: \(error.localizedDescription, privacy: .public)")
	  }

	}
	if let error = enumeratorError {
		Logger.services.error("💥 AllocatedSizeOfDirectory enumeratorError = \(error.localizedDescription, privacy: .public)")
	}

	return Double(accumulatedSize).toBytes

  }

}
