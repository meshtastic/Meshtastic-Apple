//
//  KMZArchive.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/24/26.
//
//  Reads the entries of a KMZ, which is a ZIP holding a KML document and the images it names.
//  Nothing is written to disk: an entry is inflated in memory, and only when asked for, so an
//  archive costs what its KML and the images the map actually draws cost.
//

import Compression
import Foundation

enum KMZArchiveError: Error, LocalizedError {
	case notAnArchive
	case noKML
	case tooLarge
	case corrupt

	var errorDescription: String? {
		switch self {
		case .notAnArchive:
			return String(localized: "This file is not a KMZ archive.")
		case .noKML:
			return String(localized: "This KMZ archive has no KML document in it.")
		case .tooLarge:
			return String(localized: "This KMZ archive is too large once unpacked.")
		case .corrupt:
			return String(localized: "This KMZ archive is damaged and could not be read.")
		}
	}
}

final class KMZArchive {
	/// The most the whole archive may inflate to, counting every entry read. A ZIP's inflated size
	/// has nothing to do with its size on disk, and these files arrive from anywhere.
	static let maxInflatedBytes = 50 * 1024 * 1024
	/// An archive with more entries than this is not a map.
	private static let maxEntries = 10_000

	struct Entry {
		let name: String
		let method: UInt16
		let isEncrypted: Bool
		let compressedSize: Int
		let uncompressedSize: Int
		let localHeaderOffset: Int
	}

	private let data: Data
	private(set) var entries: [Entry] = []
	private var budget: Int

	/// True when `data` starts with a ZIP local file header. Checked by content, not file name,
	/// because people rename these.
	static func isArchive(_ data: Data) -> Bool {
		data.count >= 4 && data.starts(with: [0x50, 0x4B, 0x03, 0x04])
	}

	init(data: Data, maxInflatedBytes: Int = KMZArchive.maxInflatedBytes) throws {
		guard Self.isArchive(data) else { throw KMZArchiveError.notAnArchive }
		self.data = data
		self.budget = maxInflatedBytes
		try readDirectory()
	}

	// MARK: - Entries

	/// The KML document: `doc.kml` when there is one, otherwise the `.kml` nearest the root.
	func kmlData() throws -> Data {
		let candidates = entries.filter { Self.isKML($0.name) }
		let chosen = candidates.first { $0.name.lowercased() == "doc.kml" }
			?? candidates.min { $0.name.split(separator: "/").count < $1.name.split(separator: "/").count }
		guard let chosen else { throw KMZArchiveError.noKML }
		return try inflate(chosen)
	}

	/// The bytes of the entry a KML `href` names, or nil when the archive doesn't hold it, it's a
	/// web address (nothing here fetches those), or the budget is spent.
	func data(forHref href: String) -> Data? {
		guard let entry = entry(forHref: href) else { return nil }
		return try? inflate(entry)
	}

	func entry(forHref href: String) -> Entry? {
		var path = href.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !path.isEmpty, URL(string: path)?.scheme == nil else { return nil }
		while path.hasPrefix("./") { path.removeFirst(2) }
		let decoded = path.removingPercentEncoding ?? path
		let usable = entries.filter { !$0.name.hasSuffix("/") }
		if let exact = usable.first(where: { $0.name == path || $0.name == decoded }) { return exact }
		let lowered = decoded.lowercased()
		if let loose = usable.first(where: { $0.name.lowercased() == lowered }) { return loose }
		// Some exporters write the bare file name for an image kept in a folder.
		let base = (decoded as NSString).lastPathComponent.lowercased()
		let sameName = usable.filter { ($0.name as NSString).lastPathComponent.lowercased() == base }
		return sameName.count == 1 ? sameName[0] : nil
	}

	private static func isKML(_ name: String) -> Bool {
		name.lowercased().hasSuffix(".kml") && !isJunk(name)
	}

	private static func isJunk(_ name: String) -> Bool {
		name.hasPrefix("__MACOSX/") || name.hasSuffix("/")
			|| (name as NSString).lastPathComponent.hasPrefix(".")
	}

	// MARK: - Directory

	private func readDirectory() throws {
		guard let end = findEndOfCentralDirectory() else { throw KMZArchiveError.corrupt }
		let count = Int(readUInt16(at: end + 10))
		let size = Int(readUInt32(at: end + 12))
		let offset = Int(readUInt32(at: end + 16))
		// A ZIP64 archive writes these as all ones. Map exports aren't that big.
		guard count != 0xFFFF, size != 0xFFFF_FFFF, offset != 0xFFFF_FFFF,
			  count <= Self.maxEntries, offset + size <= data.count else { throw KMZArchiveError.corrupt }

		var cursor = offset
		for _ in 0..<count {
			guard cursor + 46 <= data.count, readUInt32(at: cursor) == 0x0201_4B50 else { throw KMZArchiveError.corrupt }
			let flags = readUInt16(at: cursor + 8)
			let method = readUInt16(at: cursor + 10)
			let compressed = readUInt32(at: cursor + 20)
			let uncompressed = readUInt32(at: cursor + 24)
			let nameLength = Int(readUInt16(at: cursor + 28))
			let extraLength = Int(readUInt16(at: cursor + 30))
			let commentLength = Int(readUInt16(at: cursor + 32))
			let localOffset = readUInt32(at: cursor + 42)
			let nameStart = cursor + 46
			guard nameStart + nameLength + extraLength + commentLength <= data.count else { throw KMZArchiveError.corrupt }
			let nameBytes = data[(data.startIndex + nameStart)..<(data.startIndex + nameStart + nameLength)]
			let name = String(data: Data(nameBytes), encoding: .utf8)
				?? String(data: Data(nameBytes), encoding: .isoLatin1) ?? ""
			cursor = nameStart + nameLength + extraLength + commentLength

			guard compressed != 0xFFFF_FFFF, uncompressed != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF else { continue }
			entries.append(Entry(
				name: name,
				method: method,
				isEncrypted: flags & 0x1 != 0,
				compressedSize: Int(compressed),
				uncompressedSize: Int(uncompressed),
				localHeaderOffset: Int(localOffset)
			))
		}
	}

	private func findEndOfCentralDirectory() -> Int? {
		guard data.count >= 22 else { return nil }
		// The record is 22 bytes plus a comment of up to 65,535, at the very end.
		let lowest = max(0, data.count - 22 - 0xFFFF)
		var position = data.count - 22
		while position >= lowest {
			if readUInt32(at: position) == 0x0605_4B50 { return position }
			position -= 1
		}
		return nil
	}

	// MARK: - Inflating

	private func inflate(_ entry: Entry) throws -> Data {
		guard !entry.isEncrypted, entry.method == 0 || entry.method == 8 else { throw KMZArchiveError.corrupt }
		guard entry.uncompressedSize <= budget else { throw KMZArchiveError.tooLarge }

		let header = entry.localHeaderOffset
		guard header >= 0, header + 30 <= data.count, readUInt32(at: header) == 0x0403_4B50 else {
			throw KMZArchiveError.corrupt
		}
		let nameLength = Int(readUInt16(at: header + 26))
		let extraLength = Int(readUInt16(at: header + 28))
		let start = header + 30 + nameLength + extraLength
		guard start >= 0, start + entry.compressedSize <= data.count else { throw KMZArchiveError.corrupt }
		budget -= entry.uncompressedSize
		if entry.uncompressedSize == 0 { return Data() }

		let source = data[(data.startIndex + start)..<(data.startIndex + start + entry.compressedSize)]
		if entry.method == 0 {
			guard entry.compressedSize == entry.uncompressedSize else { throw KMZArchiveError.corrupt }
			return Data(source)
		}

		// A ZIP entry is raw DEFLATE, which is what COMPRESSION_ZLIB decodes.
		var output = Data(count: entry.uncompressedSize)
		let written: Int = output.withUnsafeMutableBytes { destination in
			source.withUnsafeBytes { input in
				guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
					  let inputBase = input.bindMemory(to: UInt8.self).baseAddress else { return 0 }
				return compression_decode_buffer(
					destinationBase, entry.uncompressedSize,
					inputBase, entry.compressedSize,
					nil, COMPRESSION_ZLIB
				)
			}
		}
		// Fewer bytes than the directory promised means the entry is damaged (or lying).
		guard written == entry.uncompressedSize else { throw KMZArchiveError.corrupt }
		return output
	}

	// MARK: - Little-endian reads

	private func readUInt16(at offset: Int) -> UInt16 {
		guard offset >= 0, offset + 2 <= data.count else { return 0 }
		let base = data.startIndex + offset
		return UInt16(data[base]) | UInt16(data[base + 1]) << 8
	}

	private func readUInt32(at offset: Int) -> UInt32 {
		guard offset >= 0, offset + 4 <= data.count else { return 0 }
		let base = data.startIndex + offset
		return UInt32(data[base]) | UInt32(data[base + 1]) << 8
			| UInt32(data[base + 2]) << 16 | UInt32(data[base + 3]) << 24
	}
}
