//
//  EXICodec.swift
//  Meshtastic
//
//  Zlib compression for CoT events over mesh network.
//  Uses standard zlib format (78 xx header) for Android interoperability.
//
//  IMPORTANT: Uses C zlib library directly to produce standard zlib format.
//  Apple's Compression framework produces raw deflate which is NOT compatible
//  with Android's standard zlib decompressor.
//
//  Zlib header bytes:
//  - 78 01: No compression
//  - 78 9C: Default compression (what we use)
//  - 78 DA: Best compression
//

import Foundation
import zlib
import OSLog

/// Codec for compressing/decompressing CoT XML using standard zlib
/// Named EXICodec for historical reasons - now uses zlib for Android compatibility
final class EXICodec {

	static let shared = EXICodec()

	private init() {}

	// MARK: - Compression

	/// Compress CoT XML to binary format using zlib
	/// - Parameter xml: The CoT XML string
	/// - Returns: Compressed data (78 9C header), or nil if compression failed
	func compress(_ xml: String) -> Data? {
		guard let xmlData = xml.data(using: .utf8) else {
			Logger.tak.error("Zlib: Failed to convert XML to UTF-8 data")
			return nil
		}

		// Use standard zlib compression (produces 78 9C header that Android expects)
		guard let compressed = compressZlib(xmlData) else {
			Logger.tak.warning("Zlib: Compression failed, using raw data")
			return xmlData
		}

		let ratio = Double(compressed.count) / Double(xmlData.count) * 100
		Logger.tak.info("Zlib: Compressed \(xmlData.count) → \(compressed.count) bytes (\(String(format: "%.1f", ratio))%)")

		// Log first few bytes to verify format (should start with 78 9C)
		if compressed.count >= 2 {
			Logger.tak.debug("Zlib: Header: \(String(format: "%02X %02X", compressed[0], compressed[1]))")
		}

		return compressed
	}

	/// Decompress zlib data to CoT XML
	/// - Parameter data: The compressed data (expects 78 xx header)
	/// - Returns: Decompressed XML string, or nil if decompression failed
	func decompress(_ data: Data) -> String? {
		// Log header for debugging
		if data.count >= 2 {
			Logger.tak.debug("Zlib: Decompressing data with header: \(String(format: "%02X %02X", data[0], data[1]))")
		}

		// Try standard zlib decompression (78 xx header)
		if let decompressed = decompressZlib(data) {
			if let xml = String(data: decompressed, encoding: .utf8) {
				Logger.tak.debug("Zlib: Decompressed \(data.count) → \(decompressed.count) bytes")
				return xml
			}
		}

		// Fallback: try interpreting as raw UTF-8 (uncompressed)
		if let xml = String(data: data, encoding: .utf8) {
			Logger.tak.debug("Zlib: Data was uncompressed UTF-8 (\(data.count) bytes)")
			return xml
		}

		Logger.tak.error("Zlib: Failed to decompress data (\(data.count) bytes)")
		return nil
	}

	// MARK: - Zlib Implementation

	/// Compress data using standard zlib format (78 9C header)
	/// Uses C zlib library directly for Android compatibility
	private func compressZlib(_ data: Data) -> Data? {
		// Calculate maximum compressed size
		var compressedLength = compressBound(uLong(data.count))
		var compressed = Data(count: Int(compressedLength))

		let result = compressed.withUnsafeMutableBytes { destPtr in
			data.withUnsafeBytes { srcPtr in
				compress2(
					destPtr.bindMemory(to: Bytef.self).baseAddress!,
					&compressedLength,
					srcPtr.bindMemory(to: Bytef.self).baseAddress!,
					uLong(data.count),
					Z_DEFAULT_COMPRESSION
				)
			}
		}

		guard result == Z_OK else {
			Logger.tak.error("Zlib: compress2 failed with code \(result)")
			return nil
		}

		return compressed.prefix(Int(compressedLength))
	}

	/// Decompress standard zlib data (78 xx header)
	private func decompressZlib(_ data: Data) -> Data? {
		// Estimate uncompressed size (start with 10x, will retry if needed)
		var uncompressedLength = uLong(data.count * 10)
		var maxAttempts = 3

		while maxAttempts > 0 {
			var uncompressed = Data(count: Int(uncompressedLength))

			let result = uncompressed.withUnsafeMutableBytes { destPtr in
				data.withUnsafeBytes { srcPtr in
					uncompress(
						destPtr.bindMemory(to: Bytef.self).baseAddress!,
						&uncompressedLength,
						srcPtr.bindMemory(to: Bytef.self).baseAddress!,
						uLong(data.count)
					)
				}
			}

			if result == Z_OK {
				return uncompressed.prefix(Int(uncompressedLength))
			} else if result == Z_BUF_ERROR {
				// Buffer too small, try larger
				uncompressedLength *= 2
				maxAttempts -= 1
			} else {
				Logger.tak.debug("Zlib: uncompress failed with code \(result)")
				return nil
			}
		}

		return nil
	}
}
