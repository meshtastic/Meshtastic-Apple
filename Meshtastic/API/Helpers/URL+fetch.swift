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

	/// Fetches data and the response's ETag, so a caller can tell an unchanged payload from a new
	/// one and skip the work of decoding and re-writing it.
	///
	/// The network saving is already handled beneath this: URLSession revalidates with
	/// `If-None-Match` on its own and a 304 costs an empty body. What the ETag buys the caller is
	/// the database pass — re-upserting a catalog that has not changed is pure cost.
	/// - Returns: The `Data`, and the ETag if the server sent one. Local files have no ETag.
	func dataWithETag(timeout: TimeInterval) async throws -> (data: Data, eTag: String?) {
		if isFileURL {
			return (try await data(timeout: timeout), nil)
		}
		return try await withThrowingTaskGroup(of: (Data, String?).self) { group in
			group.addTask {
				let (data, response) = try await URLSession.shared.data(from: self)
				guard let response = response as? HTTPURLResponse,
					  (200..<300).contains(response.statusCode) else {
					throw URLError(.badServerResponse)
				}
				return (data, response.value(forHTTPHeaderField: "ETag"))
			}
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
				throw TimeoutError.timedOut(timeout)
			}
			guard let result = try await group.next() else { throw URLError(.unknown) }
			group.cancelAll()
			return result
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

}
