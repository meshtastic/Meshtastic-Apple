//
//  URLSession+fetch.swift
//  Meshtastic
//
//  Created by jake on 12/6/25.
//

import Foundation

extension URLSessionConfiguration {
	/// Network policy for the catalog, firmware, image, and link requests.
	static var meshtasticAPI: URLSessionConfiguration {
		let configuration = URLSessionConfiguration.default
		configuration.timeoutIntervalForRequest = 5
		configuration.timeoutIntervalForResource = 10
		return configuration
	}
}

extension URLSession {
	/// Fetches data and the response's ETag, so a caller can skip decoding and saving unchanged data.
	func dataWithETag(from url: URL) async throws -> (data: Data, eTag: String?) {
		try await dataWithETag(for: URLRequest(url: url))
	}

	/// Fetches a configured request and its response ETag.
	func dataWithETag(for request: URLRequest) async throws -> (data: Data, eTag: String?) {
		let (data, response) = try await data(for: request)
		guard let response = response as? HTTPURLResponse,
			  (200..<300).contains(response.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return (data, response.value(forHTTPHeaderField: "ETag"))
	}
}
