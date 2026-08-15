// MARK: EventFirmwareArtifactDownloader.swift

import CryptoKit
import Foundation

enum EventFirmwareArtifactDownloadError: Error, Equatable {
	case unexpectedResponseURL
	case httpStatus(Int)
	case byteCountMismatch
	case checksumMismatch
}

actor EventFirmwareArtifactDownloader {
	typealias Download = @Sendable (URL, Int64) async throws -> (URL, URLResponse)

	private let cacheDirectory: URL
	private let download: Download

	init(
		cacheDirectory: URL = FileManager.default.urls(
			for: .cachesDirectory,
			in: .userDomainMask
		)[0].appendingPathComponent("EventFirmware", isDirectory: true),
		session: URLSession = .shared
	) {
		self.cacheDirectory = cacheDirectory
		download = { url, maximumByteCount in
			let delegate = EventFirmwareBoundedDownloadDelegate(
				maximumByteCount: maximumByteCount
			)
			do {
				return try await session.download(
					for: URLRequest(url: url),
					delegate: delegate
				)
			} catch {
				if delegate.exceededMaximumByteCount {
					throw EventFirmwareArtifactDownloadError.byteCountMismatch
				}
				throw error
			}
		}
	}

	init(
		cacheDirectory: URL,
		download: @escaping Download
	) {
		self.cacheDirectory = cacheDirectory
		self.download = download
	}

	func prepare(_ artifact: EventFirmwareOTAArtifact) async throws -> URL {
		try Task.checkCancellation()
		try FileManager.default.createDirectory(
			at: cacheDirectory,
			withIntermediateDirectories: true
		)

		let destination = cacheDirectory.appendingPathComponent(
			artifact.sha256.lowercased()
		).appendingPathExtension(artifact.format.fileExtension)
		if FileManager.default.fileExists(atPath: destination.path) {
			if (try? verify(file: destination, against: artifact)) == true {
				return destination
			}
			try FileManager.default.removeItem(at: destination)
		}

		let (downloadedURL, response) = try await download(
			artifact.url,
			artifact.byteCount
		)
		try Task.checkCancellation()
		guard response.url == artifact.url else {
			throw EventFirmwareArtifactDownloadError.unexpectedResponseURL
		}
		if let httpResponse = response as? HTTPURLResponse,
		   !(200...299).contains(httpResponse.statusCode) {
			throw EventFirmwareArtifactDownloadError.httpStatus(httpResponse.statusCode)
		}

		let stagingURL = cacheDirectory.appendingPathComponent(
			".\(UUID().uuidString).partial"
		)
		defer {
			try? FileManager.default.removeItem(at: stagingURL)
		}
		try FileManager.default.moveItem(at: downloadedURL, to: stagingURL)
		guard try verify(file: stagingURL, against: artifact) else {
			throw EventFirmwareArtifactDownloadError.checksumMismatch
		}
		try FileManager.default.moveItem(at: stagingURL, to: destination)
		return destination
	}

	private func verify(
		file: URL,
		against artifact: EventFirmwareOTAArtifact
	) throws -> Bool {
		let verification = try digestAndSize(of: file)
		guard verification.byteCount == artifact.byteCount else {
			throw EventFirmwareArtifactDownloadError.byteCountMismatch
		}
		return verification.sha256.caseInsensitiveCompare(artifact.sha256) == .orderedSame
	}

	private func digestAndSize(of file: URL) throws -> (sha256: String, byteCount: Int64) {
		let handle = try FileHandle(forReadingFrom: file)
		defer {
			try? handle.close()
		}
		var hasher = SHA256()
		var byteCount: Int64 = 0
		while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
			try Task.checkCancellation()
			byteCount += Int64(chunk.count)
			hasher.update(data: chunk)
		}
		let sha256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
		return (sha256, byteCount)
	}
}

/// Cancels a URL session download task as soon as its streamed byte count exceeds a trusted limit.
final class EventFirmwareBoundedDownloadDelegate: NSObject,
	URLSessionDownloadDelegate,
	@unchecked Sendable {

	private let maximumByteCount: Int64
	private let lock = NSLock()
	private var exceeded = false

	var exceededMaximumByteCount: Bool {
		lock.withLock { exceeded }
	}

	init(maximumByteCount: Int64) {
		self.maximumByteCount = maximumByteCount
	}

	func urlSession(
		_ session: URLSession,
		downloadTask: URLSessionDownloadTask,
		didFinishDownloadingTo location: URL
	) {}

	func urlSession(
		_ session: URLSession,
		downloadTask: URLSessionDownloadTask,
		didWriteData bytesWritten: Int64,
		totalBytesWritten: Int64,
		totalBytesExpectedToWrite: Int64
	) {
		guard totalBytesWritten > maximumByteCount else { return }
		lock.withLock {
			exceeded = true
		}
		downloadTask.cancel()
	}
}

private extension EventFirmwareOTAArtifact.Format {
	var fileExtension: String {
		switch self {
		case .bin:
			return "bin"
		case .otaZip:
			return "zip"
		}
	}
}
