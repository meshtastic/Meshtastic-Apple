// URLExtensionDetailedTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

// MARK: - URL queryParam subscript Tests

@Suite("URL queryParam Subscript")
struct URLQueryParamSubscriptTests {

	@Test func queryParam_existingKey() {
		let url = URL(string: "https://example.com?key=value&foo=bar")!
		#expect(url["key"] == "value")
		#expect(url["foo"] == "bar")
	}

	@Test func queryParam_missingKey() {
		let url = URL(string: "https://example.com?key=value")!
		#expect(url["missing"] == nil)
	}

	@Test func queryParam_noQueryString() {
		let url = URL(string: "https://example.com/path")!
		#expect(url["key"] == nil)
	}

	@Test func queryParam_emptyValue() {
		let url = URL(string: "https://example.com?key=")!
		#expect(url["key"] == "")
	}

	@Test func queryParam_encodedValue() {
		let url = URL(string: "https://example.com?name=hello%20world")!
		#expect(url["name"] == "hello world")
	}

	@Test func queryParam_fragmentParam() {
		let url = URL(string: "https://example.com#section?key=value")!
		#expect(url["key"] == "value")
	}
}

// MARK: - URL queryParameters Tests

@Suite("URL queryParameters Extended")
struct URLQueryParametersExtendedTests {

	@Test func queryParameters_multipleParams() {
		let url = URL(string: "https://example.com?a=1&b=2&c=3")!
		let params = url.queryParameters
		#expect(params?["a"] == "1")
		#expect(params?["b"] == "2")
		#expect(params?["c"] == "3")
	}

	@Test func queryParameters_noParams() {
		let url = URL(string: "https://example.com")!
		#expect(url.queryParameters == nil)
	}

	@Test func queryParameters_singleParam() {
		let url = URL(string: "https://example.com?only=one")!
		let params = url.queryParameters
		#expect(params?.count == 1)
		#expect(params?["only"] == "one")
	}
}

// MARK: - URL fileSizeString Tests

@Suite("URL File Properties")
struct URLFilePropertiesTests {

	@Test func fileSizeString_nonExistentFile() {
		let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")
		#expect(url.fileSizeString == "Zero KB")
	}

	@Test func fileSize_nonExistentFile() {
		let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")
		#expect(url.fileSize == 0)
	}

	@Test func creationDate_nonExistentFile() {
		let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")
		#expect(url.creationDate == nil)
	}

	@Test func attributes_nonExistentFile() {
		let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")
		#expect(url.attributes == nil)
	}
}

// MARK: - URL regularFileAllocatedSize Tests

@Suite("URL regularFileAllocatedSize")
struct URLRegularFileAllocatedSizeTests {

	@Test func regularFile_returnsSize() throws {
		let tmpDir = FileManager.default.temporaryDirectory
		let file = tmpDir.appendingPathComponent("test_alloc_\(UUID().uuidString).txt")
		let data = Data(repeating: 0x42, count: 256)
		try data.write(to: file)
		defer { try? FileManager.default.removeItem(at: file) }

		let size = try file.regularFileAllocatedSize()
		#expect(size > 0)
	}

	@Test func directory_returnsZero() throws {
		let tmpDir = FileManager.default.temporaryDirectory
		let dir = tmpDir.appendingPathComponent("test_dir_\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let size = try dir.regularFileAllocatedSize()
		#expect(size == 0)
	}
}
