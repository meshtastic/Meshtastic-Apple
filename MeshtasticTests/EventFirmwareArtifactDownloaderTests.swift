// MARK: EventFirmwareArtifactDownloaderTests.swift

import CryptoKit
import Foundation
import Testing

@testable import Meshtastic

@Suite("Event firmware artifact downloader", .serialized)
struct EventFirmwareArtifactDownloaderTests {

	@Test func downloadsVerifiesAndCachesArtifact() async throws {
		let fixture = try Fixture(payload: Data("verified firmware".utf8))
		let downloader = EventFirmwareArtifactDownloader(
			cacheDirectory: fixture.cacheDirectory,
			download: { _, _ in (fixture.downloadedFile, try fixture.response()) }
		)

		let localURL = try await downloader.prepare(fixture.artifact())

		#expect(FileManager.default.fileExists(atPath: localURL.path))
		#expect(try Data(contentsOf: localURL) == fixture.payload)
		#expect(localURL.pathExtension == "bin")
	}

	@Test func reusesVerifiedCacheWithoutDownloadingAgain() async throws {
		let fixture = try Fixture(payload: Data("cached firmware".utf8))
		let counter = DownloadCounter()
		let downloader = EventFirmwareArtifactDownloader(
			cacheDirectory: fixture.cacheDirectory,
			download: { _, _ in
				await counter.increment()
				return (fixture.downloadedFile, try fixture.response())
			}
		)

		_ = try await downloader.prepare(fixture.artifact())
		_ = try await downloader.prepare(fixture.artifact())

		#expect(await counter.value == 1)
	}

	@Test func replacesInvalidCachedFile() async throws {
		let fixture = try Fixture(payload: Data("replacement firmware".utf8))
		let artifact = fixture.artifact()
		try FileManager.default.createDirectory(
			at: fixture.cacheDirectory,
			withIntermediateDirectories: true
		)
		let cachedFile = fixture.cacheDirectory
			.appendingPathComponent(artifact.sha256)
			.appendingPathExtension("bin")
		try Data("truncated".utf8).write(to: cachedFile)
		let downloader = EventFirmwareArtifactDownloader(
			cacheDirectory: fixture.cacheDirectory,
			download: { _, _ in (fixture.downloadedFile, try fixture.response()) }
		)

		let localURL = try await downloader.prepare(artifact)

		#expect(localURL == cachedFile)
		#expect(try Data(contentsOf: localURL) == fixture.payload)
	}

	@Test func passesSignedByteCountAsDownloadCeiling() async throws {
		let fixture = try Fixture(payload: Data("bounded firmware".utf8))
		let recorder = DownloadLimitRecorder()
		let downloader = EventFirmwareArtifactDownloader(
			cacheDirectory: fixture.cacheDirectory,
			download: { _, maximumByteCount in
				await recorder.record(maximumByteCount)
				return (fixture.downloadedFile, try fixture.response())
			}
		)

		_ = try await downloader.prepare(fixture.artifact())

		#expect(await recorder.value == Int64(fixture.payload.count))
	}

	@Test func rejectsByteCountMismatchAndRemovesStagingFile() async throws {
		let fixture = try Fixture(payload: Data("short".utf8))
		let downloader = EventFirmwareArtifactDownloader(
			cacheDirectory: fixture.cacheDirectory,
			download: { _, _ in (fixture.downloadedFile, try fixture.response()) }
		)
		let artifact = fixture.artifact(byteCount: Int64(fixture.payload.count + 1))

		await #expect(throws: EventFirmwareArtifactDownloadError.byteCountMismatch) {
			try await downloader.prepare(artifact)
		}
		#expect(try fixture.cachedFiles().isEmpty)
	}

	@Test func rejectsChecksumMismatchAndRemovesStagingFile() async throws {
		let fixture = try Fixture(payload: Data("wrong digest".utf8))
		let downloader = EventFirmwareArtifactDownloader(
			cacheDirectory: fixture.cacheDirectory,
			download: { _, _ in (fixture.downloadedFile, try fixture.response()) }
		)
		let artifact = fixture.artifact(sha256: String(repeating: "0", count: 64))

		await #expect(throws: EventFirmwareArtifactDownloadError.checksumMismatch) {
			try await downloader.prepare(artifact)
		}
		#expect(try fixture.cachedFiles().isEmpty)
	}

	@Test func rejectsRedirectedFinalURL() async throws {
		let fixture = try Fixture(payload: Data("redirected".utf8))
		let redirectedURL = try #require(URL(string: "https://evil.example/firmware.bin"))
		let downloader = EventFirmwareArtifactDownloader(
			cacheDirectory: fixture.cacheDirectory,
			download: { _, _ in (fixture.downloadedFile, try fixture.response(url: redirectedURL)) }
		)

		await #expect(throws: EventFirmwareArtifactDownloadError.unexpectedResponseURL) {
			try await downloader.prepare(fixture.artifact())
		}
	}

	@Test func rejectsNonSuccessHTTPStatus() async throws {
		let fixture = try Fixture(payload: Data("not firmware".utf8))
		let downloader = EventFirmwareArtifactDownloader(
			cacheDirectory: fixture.cacheDirectory,
			download: { _, _ in (fixture.downloadedFile, try fixture.response(statusCode: 404)) }
		)

		await #expect(throws: EventFirmwareArtifactDownloadError.httpStatus(404)) {
			try await downloader.prepare(fixture.artifact())
		}
	}

	private actor DownloadCounter {
		private(set) var value = 0
		func increment() {
			value += 1
		}
	}

	private actor DownloadLimitRecorder {
		private(set) var value: Int64?
		func record(_ value: Int64) {
			self.value = value
		}
	}

	private struct Fixture {
		let payload: Data
		let remoteURL: URL
		let rootDirectory: URL
		let cacheDirectory: URL
		let downloadedFile: URL

		init(payload: Data) throws {
			self.payload = payload
			remoteURL = try #require(URL(
				string: "https://raw.githubusercontent.com/meshtastic/firmware/" +
					"0123456789abcdef0123456789abcdef01234567/firmware.bin"
			))
			rootDirectory = FileManager.default.temporaryDirectory
				.appendingPathComponent(UUID().uuidString, isDirectory: true)
			cacheDirectory = rootDirectory.appendingPathComponent("cache", isDirectory: true)
			downloadedFile = rootDirectory.appendingPathComponent("download.tmp")
			try FileManager.default.createDirectory(
				at: rootDirectory,
				withIntermediateDirectories: true
			)
			try payload.write(to: downloadedFile)
		}

		func artifact(
			sha256: String? = nil,
			byteCount: Int64? = nil
		) -> EventFirmwareOTAArtifact {
			EventFirmwareOTAArtifact(
				pioEnv: "tbeam-s3-core",
				hwModel: 12,
				architecture: Architecture.esp32S3.rawValue,
				version: "2.8.0.b00d76f",
				format: .bin,
				url: remoteURL,
				sha256: sha256 ?? SHA256.hash(data: payload).hexString,
				byteCount: byteCount ?? Int64(payload.count),
				minimumSourceVersion: "2.7.0",
				partitionRole: "app0",
				partitionScheme: "8MB",
				dfuProtocol: nil,
				minimumBootloaderVersion: nil
			)
		}

		func response(
			statusCode: Int = 200,
			url: URL? = nil
		) throws -> HTTPURLResponse {
			try #require(HTTPURLResponse(
				url: url ?? remoteURL,
				statusCode: statusCode,
				httpVersion: "HTTP/1.1",
				headerFields: ["Content-Type": "application/octet-stream"]
			))
		}

		func cachedFiles() throws -> [URL] {
			guard FileManager.default.fileExists(atPath: cacheDirectory.path) else { return [] }
			return try FileManager.default.contentsOfDirectory(
				at: cacheDirectory,
				includingPropertiesForKeys: nil
			)
		}
	}
}

private extension SHA256.Digest {
	var hexString: String {
		map { String(format: "%02x", $0) }.joined()
	}
}
