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
	var queryParameters: [String: String]? {
		guard let components = URLComponents(url: self, resolvingAgainstBaseURL: true),
			  let queryItems = components.queryItems else {
			return nil
		}

		var parameters = [String: String]()
		for item in queryItems {
			parameters[item.name] = item.value
		}
		return parameters
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
	
	/// Checks if the URL points to a valid file without downloading the body.
	 /// - Parameter timeout: How long to wait before failing (default: 5 seconds).
	 /// - Returns: True if the server returns a 200 OK status.
	 func isValidDownload(timeout: TimeInterval = 5.0) async -> Bool {
		 var request = URLRequest(url: self)
		 request.httpMethod = "HEAD"
		 request.timeoutInterval = timeout
		 
		 do {
			 let (_, response) = try await URLSession.shared.data(for: request)
			 
			 guard let httpResponse = response as? HTTPURLResponse else {
				 return false
			 }
			 
			 // Accept 200 (OK).
			 // Depending on your needs, you might also accept 200...299
			 return httpResponse.statusCode == 200
		 } catch {
			 return false
		 }
	 }
	 
	 /// Checks if the URL points to a valid file (Closure based for older iOS).
	 func isValidDownload(timeout: TimeInterval = 5.0, completion: @escaping (Bool) -> Void) {
		 var request = URLRequest(url: self)
		 request.httpMethod = "HEAD"
		 request.timeoutInterval = timeout
		 
		 let task = URLSession.shared.dataTask(with: request) { _, response, error in
			 if let _ = error {
				 completion(false)
				 return
			 }
			 
			 if let httpResponse = response as? HTTPURLResponse,
				httpResponse.statusCode == 200 {
				 completion(true)
			 } else {
				 completion(false)
			 }
		 }
		 task.resume()
	 }
}
