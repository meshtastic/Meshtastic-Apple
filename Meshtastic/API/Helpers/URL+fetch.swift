//
//  URL+fetch.swift
//  Meshtastic
//
//  Created by jake on 12/6/25.
//

import Foundation

extension URL {
	
	/// Custom error type for the URL extension
	enum TimeoutError: Error, LocalizedError {
		case timedOut(TimeInterval)
		
		var errorDescription: String? {
			switch self {
			case .timedOut(let seconds):
				return "The operation timed out after \(seconds) seconds."
			}
		}
	}

	/// Fetches data from the URL (local or remote) with a strict timeout.
	/// - Parameter timeout: The duration in seconds to wait before throwing an error.
	/// - Returns: The `Data` retrieved.
	func data(timeout: TimeInterval) async throws -> Data {
		
		return try await withThrowingTaskGroup(of: Data.self) { group in
			
			// Task 1: The Fetch Operation
			group.addTask {
				if self.isFileURL {
					// Handle Local Files
					// Note: Data(contentsOf:) is synchronous (blocking).
					// Running it inside a Task allows it to be raced, though
					// the underlying thread may remain blocked until OS IO completes
					// if cancellation occurs.
					return try Data(contentsOf: self)
				} else {
					// Handle Remote Network Requests
					let (data, _) = try await URLSession.shared.data(from: self)
					return data
				}
			}
			
			// Task 2: The Timer
			group.addTask {
				// Convert seconds to nanoseconds
				let nanoseconds = UInt64(timeout * 1_000_000_000)
				try await Task.sleep(nanoseconds: nanoseconds)
				
				// If we wake up, it means the fetch hasn't finished yet
				throw TimeoutError.timedOut(timeout)
			}
			
			// Race Handling
			
			// Wait for the first task to finish (either success or error)
			guard let result = try await group.next() else {
				// Should not be reachable, but required by compiler
				throw URLError(.unknown)
			}
			
			// If we are here, one task finished successfully.
			// Cancel the other task immediately.
			group.cancelAll()
			
			return result
		}
	}
	
	/// Performs a HEAD request to fetch the ETag header for the URL.
	/// - Parameter session: The URLSession to use (defaults to .shared).
	/// - Returns: The ETag string if found and the request is successful, otherwise nil.
	func eTag(using session: URLSession = .shared) async throws -> String? {
		var request = URLRequest(url: self)
		request.httpMethod = "HEAD"
		
		// Ensure we don't use the local cache so we get the real ETag from the server
		request.cachePolicy = .reloadIgnoringLocalCacheData
		
		let (_, response) = try await session.data(for: request)
		
		guard let httpResponse = response as? HTTPURLResponse else {
			return nil
		}
		
		// Optional: Check for success status codes (200-299)
		guard (200...299).contains(httpResponse.statusCode) else {
			// You might want to return nil or throw a specific error here
			// depending on your requirements (e.g. 404 Not Found)
			return nil
		}
		
		// Header lookup is case-insensitive
		return httpResponse.value(forHTTPHeaderField: "ETag")
	}
}
