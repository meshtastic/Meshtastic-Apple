//
//  KMZArchiveTests.swift
//  MeshtasticTests
//

import Compression
import Foundation
import Testing
@testable import Meshtastic

/// Builds ZIP archives by hand, so the reader is tested against bytes it did not write itself.
enum TestZip {
	struct Entry {
		var name: String
		var data: Data
		var deflate = false
		var flags: UInt16 = 0
		/// What the central directory claims the entry inflates to, when it should lie about it.
		var declaredUncompressedSize: Int?
	}

	static func make(_ entries: [Entry], comment: String = "") -> Data {
		var body = Data()
		var directory = Data()
		for entry in entries {
			let stored = entry.deflate ? deflated(entry.data) : entry.data
			let offset = body.count
			let name = Data(entry.name.utf8)
			// Local file header.
			body.append(le32(0x0403_4B50))
			body.append(le16(20))
			body.append(le16(entry.flags))
			body.append(le16(entry.deflate ? 8 : 0))
			body.append(contentsOf: [0, 0, 0, 0])
			body.append(le32(0))
			body.append(le32(UInt32(stored.count)))
			body.append(le32(UInt32(entry.data.count)))
			body.append(le16(UInt16(name.count)))
			body.append(le16(0))
			body.append(name)
			body.append(stored)
			// Central directory entry.
			directory.append(le32(0x0201_4B50))
			directory.append(le16(20))
			directory.append(le16(20))
			directory.append(le16(entry.flags))
			directory.append(le16(entry.deflate ? 8 : 0))
			directory.append(contentsOf: [0, 0, 0, 0])
			directory.append(le32(0))
			directory.append(le32(UInt32(stored.count)))
			directory.append(le32(UInt32(entry.declaredUncompressedSize ?? entry.data.count)))
			directory.append(le16(UInt16(name.count)))
			directory.append(le16(0))
			directory.append(le16(0))
			directory.append(le16(0))
			directory.append(le16(0))
			directory.append(le32(0))
			directory.append(le32(UInt32(offset)))
			directory.append(name)
		}
		let directoryOffset = body.count
		var archive = body
		archive.append(directory)
		let commentBytes = Data(comment.utf8)
		archive.append(le32(0x0605_4B50))
		archive.append(le16(0))
		archive.append(le16(0))
		archive.append(le16(UInt16(entries.count)))
		archive.append(le16(UInt16(entries.count)))
		archive.append(le32(UInt32(directory.count)))
		archive.append(le32(UInt32(directoryOffset)))
		archive.append(le16(UInt16(commentBytes.count)))
		archive.append(commentBytes)
		return archive
	}

	/// Raw DEFLATE, which is what a ZIP entry holds and what COMPRESSION_ZLIB writes.
	static func deflated(_ data: Data) -> Data {
		guard !data.isEmpty else { return Data() }
		var output = Data(count: data.count + 1024)
		let size = output.withUnsafeMutableBytes { destination in
			data.withUnsafeBytes { source in
				compression_encode_buffer(
					destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
					source.bindMemory(to: UInt8.self).baseAddress!, source.count,
					nil, COMPRESSION_ZLIB
				)
			}
		}
		return output.prefix(size)
	}

	private static func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }

	private static func le32(_ value: UInt32) -> Data {
		Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
	}
}

@Suite("KMZ archive")
struct KMZArchiveTests {
	private let kml = Data("<kml><Document><Placemark><Point><coordinates>1,1</coordinates></Point></Placemark></Document></kml>".utf8)

	@Test("A stored entry and a deflated one both read back")
	func storedAndDeflated() throws {
		let image = Data((0..<2_000).map { UInt8($0 % 7) })
		let archive = try KMZArchive(data: TestZip.make([
			.init(name: "doc.kml", data: kml, deflate: true),
			.init(name: "files/pin.png", data: image, deflate: false)
		]))
		#expect(try archive.kmlData() == kml)
		#expect(archive.data(forHref: "files/pin.png") == image)
	}

	@Test("A deflated image with repeated content reads back byte for byte")
	func deflatedImage() throws {
		let image = Data(repeating: 0xAB, count: 50_000)
		let archive = try KMZArchive(data: TestZip.make([
			.init(name: "doc.kml", data: kml),
			.init(name: "big.png", data: image, deflate: true)
		]))
		#expect(archive.data(forHref: "big.png") == image)
	}

	@Test("doc.kml is preferred, then the KML nearest the root")
	func choosesTheKML() throws {
		let other = Data("<kml>other</kml>".utf8)
		let archive = try KMZArchive(data: TestZip.make([
			.init(name: "a/b/deep.kml", data: other),
			.init(name: "doc.kml", data: kml)
		]))
		#expect(try archive.kmlData() == kml)

		let shallow = try KMZArchive(data: TestZip.make([
			.init(name: "a/b/deep.kml", data: other),
			.init(name: "map.kml", data: kml)
		]))
		#expect(try shallow.kmlData() == kml)
	}

	@Test("Resource-fork junk is never taken for the KML")
	func ignoresJunk() throws {
		let archive = try KMZArchive(data: TestZip.make([
			.init(name: "__MACOSX/._doc.kml", data: Data("junk".utf8)),
			.init(name: "._hidden.kml", data: Data("junk".utf8)),
			.init(name: "doc.kml", data: kml)
		]))
		#expect(try archive.kmlData() == kml)
	}

	@Test("An archive with no KML says so")
	func noKML() throws {
		let archive = try KMZArchive(data: TestZip.make([.init(name: "readme.txt", data: Data("hi".utf8))]))
		#expect(throws: KMZArchiveError.noKML) { try archive.kmlData() }
	}

	@Test("Image references match with a leading ./, percent escapes, other case, or a bare file name")
	func hrefMatching() throws {
		let image = Data([1, 2, 3])
		let archive = try KMZArchive(data: TestZip.make([
			.init(name: "doc.kml", data: kml),
			.init(name: "files/My Pin.png", data: image)
		]))
		#expect(archive.data(forHref: "./files/My Pin.png") == image)
		#expect(archive.data(forHref: "files/My%20Pin.png") == image)
		#expect(archive.data(forHref: "FILES/MY PIN.PNG") == image)
		#expect(archive.data(forHref: "My Pin.png") == image)
		#expect(archive.data(forHref: "files/other.png") == nil)
	}

	@Test("A web address is never read from the archive")
	func webAddresses() throws {
		let archive = try KMZArchive(data: TestZip.make([
			.init(name: "doc.kml", data: kml),
			.init(name: "pin.png", data: Data([1]))
		]))
		#expect(archive.data(forHref: "https://example.org/pin.png") == nil)
		#expect(archive.data(forHref: "http://maps.google.com/mapfiles/kml/pushpin/ylw-pushpin.png") == nil)
	}

	@Test("An entry that claims to inflate past the cap is refused before anything is allocated")
	func declaredSizeOverCap() throws {
		let archive = try KMZArchive(data: TestZip.make([
			.init(name: "doc.kml", data: kml),
			.init(name: "bomb.png", data: Data([1, 2, 3]), declaredUncompressedSize: 60 * 1024 * 1024)
		]))
		#expect(archive.data(forHref: "bomb.png") == nil)
		#expect(try archive.kmlData() == kml)
	}

	@Test("One budget is shared across everything read")
	func sharedBudget() throws {
		let archive = try KMZArchive(
			data: TestZip.make([
				.init(name: "doc.kml", data: kml),
				.init(name: "a.png", data: Data(repeating: 1, count: 600)),
				.init(name: "b.png", data: Data(repeating: 2, count: 600))
			]),
			maxInflatedBytes: kml.count + 1_000
		)
		#expect(try archive.kmlData() == kml)
		#expect(archive.data(forHref: "a.png") != nil)
		#expect(archive.data(forHref: "b.png") == nil, "past the budget")
	}

	@Test("An entry that inflates to less than the directory says is damaged")
	func lyingDeflate() throws {
		let real = Data(repeating: 7, count: 100)
		let archive = try KMZArchive(data: TestZip.make([
			.init(name: "doc.kml", data: kml),
			.init(name: "short.png", data: real, deflate: true, declaredUncompressedSize: 5_000)
		]))
		#expect(archive.data(forHref: "short.png") == nil)
	}

	@Test("An encrypted entry is refused")
	func encrypted() throws {
		let archive = try KMZArchive(data: TestZip.make([.init(name: "doc.kml", data: kml, flags: 0x1)]))
		#expect(throws: KMZArchiveError.corrupt) { try archive.kmlData() }
	}

	@Test("Something that isn't a ZIP, or is cut off, is refused")
	func notAnArchive() {
		#expect(throws: KMZArchiveError.notAnArchive) { try KMZArchive(data: Data("<kml/>".utf8)) }
		#expect(throws: KMZArchiveError.notAnArchive) { try KMZArchive(data: Data()) }
		let whole = TestZip.make([.init(name: "doc.kml", data: kml)])
		#expect(throws: KMZArchiveError.corrupt) { try KMZArchive(data: whole.prefix(whole.count - 12)) }
		#expect(throws: KMZArchiveError.corrupt) { try KMZArchive(data: Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3])) }
	}

	@Test("An archive comment after the directory is skipped over")
	func archiveComment() throws {
		let archive = try KMZArchive(data: TestZip.make([.init(name: "doc.kml", data: kml)], comment: String(repeating: "x", count: 500)))
		#expect(try archive.kmlData() == kml)
	}

	@Test("Archives are recognized by their bytes, not their name")
	func recognition() {
		#expect(KMZArchive.isArchive(TestZip.make([.init(name: "doc.kml", data: kml)])))
		#expect(!KMZArchive.isArchive(kml))
	}
}
