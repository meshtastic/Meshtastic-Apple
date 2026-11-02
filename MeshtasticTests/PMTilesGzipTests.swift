//
//  PMTilesGzipTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Foundation
import Testing
import zlib

@testable import Meshtastic

@Suite("PMTiles gzip inflate")
struct PMTilesGzipTests {

	private let payload = Data((0..<20_000).map { UInt8(truncatingIfNeeded: $0 * 7 + $0 / 13) })

	/// Compresses with zlib: `windowBits` 15 + 16 writes a gzip wrapper, 15 a zlib one.
	private func deflate(_ data: Data, windowBits: Int32) throws -> Data {
		var stream = z_stream()
		try #require(deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
		defer { deflateEnd(&stream) }
		var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(data.count))))
		let status = data.withUnsafeBytes { input in
			output.withUnsafeMutableBufferPointer { buffer in
				stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
				stream.avail_in = uInt(input.count)
				stream.next_out = buffer.baseAddress
				stream.avail_out = uInt(buffer.count)
				return zlib.deflate(&stream, Z_FINISH)
			}
		}
		try #require(status == Z_STREAM_END)
		return Data(output.prefix(Int(stream.total_out)))
	}

	private func gzip(_ data: Data) throws -> Data { try deflate(data, windowBits: 15 + 16) }

	@Test func gzipInflates() throws {
		#expect(PMTilesArchive.inflate(try gzip(payload)) == payload)
	}

	@Test func zlibWrapperInflates() throws {
		#expect(PMTilesArchive.inflate(try deflate(payload, windowBits: 15)) == payload)
	}

	@Test func truncatedStreamGivesNilNotAPrefix() throws {
		let whole = try gzip(payload)
		#expect(PMTilesArchive.inflate(whole.prefix(whole.count - 5)) == nil)
		#expect(PMTilesArchive.inflate(whole.prefix(whole.count / 2)) == nil)
	}

	@Test func badCRCGivesNil() throws {
		var corrupt = try gzip(payload)
		corrupt[corrupt.count - 8] ^= 0xFF   // first byte of the CRC-32 trailer
		#expect(PMTilesArchive.inflate(corrupt) == nil)
	}

	@Test func bytesAfterTheStreamGiveNil() throws {
		#expect(PMTilesArchive.inflate(try gzip(payload) + Data([0, 1, 2])) == nil)
	}

	@Test func uncompressedPassesThroughOnlyWhenDeclared() throws {
		let compressed = try gzip(payload)
		// Declared none: returned as is, even though the bytes are gzip.
		#expect(PMTilesArchive.decode(compressed, compression: .none) == compressed)
		// Declared gzip but not gzip: rejected, not passed through.
		#expect(PMTilesArchive.decode(payload, compression: .gzip) == nil)
		#expect(PMTilesArchive.decode(compressed, compression: .gzip) == payload)
	}

	@Test func unsupportedCodecsGiveNil() {
		#expect(PMTilesArchive.decode(payload, compression: .brotli) == nil)
		#expect(PMTilesArchive.decode(payload, compression: .zstd) == nil)
	}

	@Test func outputPastTheLimitGivesNil() throws {
		let zeros = Data(count: 1 << 20)
		let compressed = try gzip(zeros)
		#expect(PMTilesArchive.inflate(compressed, limit: (1 << 20) - 1) == nil)
		#expect(PMTilesArchive.inflate(compressed, limit: 1 << 20) == zeros)
	}

	@Test func archiveReadsGzipTilesAndRejectsCorruptOnes() throws {
		let good = try gzip(Data("tile-a".utf8))
		var bad = try gzip(Data("tile-b".utf8))
		bad[bad.count - 8] ^= 0xFF
		var tileData = good
		let entries: [PMTilesArchive.Entry] = [
			.init(tileID: PMTilesArchive.zxyToTileID(z: 1, x: 0, y: 0), offset: 0, length: UInt32(good.count), runLength: 1),
			.init(tileID: PMTilesArchive.zxyToTileID(z: 1, x: 1, y: 0), offset: UInt64(good.count), length: UInt32(bad.count), runLength: 1)
		].sorted { $0.tileID < $1.tileID }
		tileData.append(bad)
		let root = PMTilesExtractor.serializeDirectory(entries)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: UInt64(tileData.count),
			numTiles: 2, bounds: GeoBounds(minLon: -180, minLat: -85, maxLon: 180, maxLat: 85),
			minZoom: 1, maxZoom: 1, tileType: .mvt, tileCompression: .gzip
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try (header + root + tileData).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let archive = try #require(PMTilesArchive(url: url))
		#expect(archive.tileData(z: 1, x: 0, y: 0) == Data("tile-a".utf8))
		#expect(archive.tileData(z: 1, x: 1, y: 0) == nil)
	}
}
