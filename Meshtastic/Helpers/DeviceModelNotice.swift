//
//  DeviceModelNotice.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Compression
import Foundation

/// Reads the copyright notice meshtastic/3d-assets embeds in each model (design#169).
///
/// The notice is the layer's documentation and asset info, so it sits in the USD crate's token
/// table. RealityKit and Model I/O don't expose either, so this reads the table directly: the
/// first file in the USDZ archive (stored, never deflated), its table of contents, then the
/// LZ4-compressed TOKENS section.
enum DeviceModelNotice {

	/// The notice, or nil when the file has none or isn't a USDZ this can read.
	static func copyright(inUSDZ url: URL) -> String? {
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
		return copyright(inUSDZData: data)
	}

	static func copyright(inUSDZData data: Data) -> String? {
		guard let crate = firstArchiveEntry(data), let tokens = tokens(inCrate: crate) else { return nil }
		return tokens.first { $0.hasPrefix("Copyright") }
	}

	/// A zip local file header at the start: the data follows the name and extra field.
	private static func firstArchiveEntry(_ data: Data) -> Data? {
		guard data.count >= 30, data.uint32(at: 0) == 0x0403_4B50, data.uint16(at: 8) == 0 else { return nil }
		let size = Int(data.uint32(at: 18))
		let start = 30 + Int(data.uint16(at: 26)) + Int(data.uint16(at: 28))
		guard start + size <= data.count else { return nil }
		return data.subdata(in: data.startIndex + start ..< data.startIndex + start + size)
	}

	private static func tokens(inCrate crate: Data) -> [String]? {
		// Tokens are compressed from crate version 0.4.0 on.
		guard crate.count >= 24, crate.prefix(8) == Data("PXR-USDC".utf8),
			  crate[crate.startIndex + 8] > 0 || crate[crate.startIndex + 9] >= 4 else { return nil }
		let toc = Int(crate.uint64(at: 16))
		guard toc + 8 <= crate.count else { return nil }
		let sectionCount = Int(crate.uint64(at: toc))
		for index in 0..<sectionCount {
			let entry = toc + 8 + index * 32
			guard entry + 32 <= crate.count else { return nil }
			let name = crate.subdata(in: crate.startIndex + entry ..< crate.startIndex + entry + 16).prefix { $0 != 0 }
			guard name == Data("TOKENS".utf8) else { continue }
			let start = Int(crate.uint64(at: entry + 16))
			guard start + 24 <= crate.count else { return nil }
			let count = Int(crate.uint64(at: start))
			let rawSize = Int(crate.uint64(at: start + 8))
			let compressedSize = Int(crate.uint64(at: start + 16))
			guard start + 24 + compressedSize <= crate.count, rawSize > 0, rawSize < 64 << 20 else { return nil }
			let compressed = crate.subdata(in: crate.startIndex + start + 24 ..< crate.startIndex + start + 24 + compressedSize)
			guard let raw = decompress(compressed, rawSize: rawSize) else { return nil }
			return raw.split(separator: 0, omittingEmptySubsequences: false).prefix(count).compactMap { String(data: Data($0), encoding: .utf8) }
		}
		return nil
	}

	/// USD's fast compression: a chunk count byte, then one raw LZ4 block when it's zero, or that
	/// many blocks each led by its compressed size.
	private static func decompress(_ data: Data, rawSize: Int) -> Data? {
		guard let chunkCount = data.first else { return nil }
		var blocks: [Data] = []
		if chunkCount == 0 {
			blocks = [data.dropFirst()]
		} else {
			var offset = 1
			for _ in 0..<chunkCount {
				guard offset + 4 <= data.count else { return nil }
				let size = Int(Int32(bitPattern: data.uint32(at: offset)))
				offset += 4
				guard size > 0, offset + size <= data.count else { return nil }
				blocks.append(data.subdata(in: data.startIndex + offset ..< data.startIndex + offset + size))
				offset += size
			}
		}
		var output = Data()
		for block in blocks {
			guard !block.isEmpty, output.count < rawSize else { return nil }
			var buffer = [UInt8](repeating: 0, count: rawSize - output.count)
			let written = Data(block).withUnsafeBytes { source in
				compression_decode_buffer(&buffer, buffer.count, source.bindMemory(to: UInt8.self).baseAddress!, block.count, nil, COMPRESSION_LZ4_RAW)
			}
			guard written > 0 else { return nil }
			output.append(contentsOf: buffer.prefix(written))
		}
		return output.count == rawSize ? output : nil
	}
}

private extension Data {
	func uint16(at offset: Int) -> UInt16 {
		withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
	}

	func uint32(at offset: Int) -> UInt32 {
		withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
	}

	func uint64(at offset: Int) -> UInt64 {
		withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
	}
}
