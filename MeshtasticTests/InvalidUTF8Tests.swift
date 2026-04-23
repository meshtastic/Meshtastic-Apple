//
//  InvalidUTF8Tests.swift
//  MeshtasticTests
//
//  Tests for CVE: invalid UTF-8 in protobuf string fields
//  causing BLE sync failure and infinite reconnect loop.
//

import Foundation
import Testing
import SwiftProtobuf
@testable import Meshtastic
import MeshtasticProtobufs

@Suite("Invalid UTF-8 Protobuf Handling")
struct InvalidUTF8Tests {

	// MARK: - Demonstrating the Issue

	/// Proves that SwiftProtobuf rejects a `FromRadio` containing invalid UTF-8
	/// in `User.long_name`. This is the root cause of the infinite BLE reconnect loop.
	@Test func fromRadioWithInvalidUTF8Throws() throws {
		// Build a valid FromRadio.nodeInfo payload, then corrupt the long_name field
		// to contain an incomplete multibyte UTF-8 sequence.
		//
		// The payload simulates: "Lunar Tower 🌙" + 0xF0 0x9F 0x97 (truncated 4-byte seq)
		let truncatedEmoji: [UInt8] = [0xF0, 0x9F, 0x97] // start of 🗼 but missing final byte

		var user = User()
		user.id = "!aabbccdd"
		user.longName = "Lunar Tower 🌙ok" // valid placeholder
		user.shortName = "LT"

		var nodeInfo = NodeInfo()
		nodeInfo.num = 0xAABBCCDD
		nodeInfo.user = user

		var fromRadio = FromRadio()
		fromRadio.id = 1
		fromRadio.payloadVariant = .nodeInfo(nodeInfo)

		// Serialize to binary, then surgically corrupt the long_name
		var data = try fromRadio.serializedData()

		// Find the valid long_name bytes and replace with the truncated emoji version
		let validName = Array("Lunar Tower 🌙ok".utf8)
		let corruptName = Array("Lunar Tower ".utf8) + [0xF0, 0x9F, 0x8C, 0x99] + truncatedEmoji

		// Patch the serialized data: find the valid name and replace it
		let patched = patchProtobufBytes(data: data, find: validName, replace: corruptName)
		#expect(patched != nil, "Failed to find and patch the long_name in serialized protobuf data")

		if let patched {
			// SwiftProtobuf should reject this due to invalid UTF-8
			#expect(throws: (any Error).self) {
				_ = try FromRadio(serializedBytes: patched)
			}
		}
	}

	/// Verifies that a `FromRadio` with valid UTF-8 (including emoji) decodes successfully.
	@Test func fromRadioWithValidUTF8Succeeds() throws {
		var user = User()
		user.id = "!aabbccdd"
		user.longName = "Lunar Tower 🌙🗼"
		user.shortName = "LT"

		var nodeInfo = NodeInfo()
		nodeInfo.num = 0xAABBCCDD
		nodeInfo.user = user

		var fromRadio = FromRadio()
		fromRadio.id = 1
		fromRadio.payloadVariant = .nodeInfo(nodeInfo)

		let data = try fromRadio.serializedData()
		let decoded = try FromRadio(serializedBytes: data)

		#expect(decoded.nodeInfo.user.longName == "Lunar Tower 🌙🗼")
	}

	/// Verifies that the second real-world case (lone lead bytes) also fails decoding.
	@Test func fromRadioWithLoneLeadBytesThrows() throws {
		var user = User()
		user.id = "!11223344"
		user.longName = "Meshtastic 37e2" // valid placeholder
		user.shortName = "MS"

		var nodeInfo = NodeInfo()
		nodeInfo.num = 0x11223344
		nodeInfo.user = user

		var fromRadio = FromRadio()
		fromRadio.id = 2
		fromRadio.payloadVariant = .nodeInfo(nodeInfo)

		var data = try fromRadio.serializedData()

		// Corrupt: replace "Meshtastic" with "Mesht\xe1\xf3tic" (lone lead multibyte bytes)
		let validName = Array("Meshtastic 37e2".utf8)
		let corruptName: [UInt8] = Array("Mesht".utf8) + [0xE1, 0xF3] + Array("tic 37e2".utf8)

		let patched = patchProtobufBytes(data: data, find: validName, replace: corruptName)
		#expect(patched != nil, "Failed to find and patch the long_name in serialized protobuf data")

		if let patched {
			#expect(throws: (any Error).self) {
				_ = try FromRadio(serializedBytes: patched)
			}
		}
	}

	// MARK: - Helpers

	/// Finds `find` in `data` and replaces it with `replace`, adjusting the
	/// preceding protobuf length varint if the replacement changes the byte count.
	/// Returns nil if `find` is not found.
	private func patchProtobufBytes(data: Data, find: [UInt8], replace: [UInt8]) -> Data? {
		let bytes = Array(data)
		guard let range = bytes.findSubarray(find) else { return nil }

		var result = bytes
		result.replaceSubrange(range, with: replace)

		let sizeDelta = replace.count - find.count
		if sizeDelta != 0 {
			// Walk backwards from the match to update enclosing length-delimited field lengths.
			// In practice, for a simple single-level patch this updates the immediate parent.
			result = adjustProtobufLengths(in: result, patchRange: range, sizeDelta: sizeDelta)
		}

		return Data(result)
	}

	/// Adjusts protobuf varint lengths that enclose the patched region.
	/// This is a simplified patcher that handles common cases in our test payloads.
	private func adjustProtobufLengths(in bytes: [UInt8], patchRange: Range<Int>, sizeDelta: Int) -> [UInt8] {
		// Re-serialize from scratch with the corrupted name injected is more reliable
		// than trying to patch varints. Since the sizeDelta is small (±few bytes),
		// we rebuild by finding length-prefixed fields and adjusting.
		//
		// For our test cases, the structure is:
		//   FromRadio { nodeInfo (field 4, LEN) { user (field 2, LEN) { long_name (field 2, LEN) { bytes } } } }
		//
		// We need to adjust 3 length prefixes. Let's walk the bytes and fix them.
		var result = bytes
		var i = 0
		while i < result.count {
			let (tag, tagLen) = decodeVarint(Array(result[i...]))
			if tagLen == 0 { break }
			let wireType = tag & 0x07
			if wireType == 2 { // length-delimited
				let (length, lenLen) = decodeVarint(Array(result[(i + tagLen)...]))
				if lenLen == 0 { break }
				let fieldStart = i + tagLen + lenLen
				let fieldEnd = fieldStart + Int(length)
				// Check if the patch range falls within this field
				if fieldStart <= patchRange.lowerBound && patchRange.upperBound <= fieldEnd {
					let newLength = Int(length) + sizeDelta
					let newLenBytes = encodeVarint(UInt64(newLength))
					let oldLenBytes = encodeVarint(UInt64(length))
					if newLenBytes.count == oldLenBytes.count {
						// Same varint size, just overwrite
						for j in 0..<newLenBytes.count {
							result[i + tagLen + j] = newLenBytes[j]
						}
					}
					// If varint size changes, this gets complex — not needed for our tests
				}
			}
			// Move to next field (simplified — just increment)
			i += 1
		}
		return result
	}

	private func decodeVarint(_ bytes: [UInt8]) -> (UInt64, Int) {
		var value: UInt64 = 0
		var shift: UInt64 = 0
		for (i, byte) in bytes.enumerated() {
			value |= UInt64(byte & 0x7F) << shift
			if byte & 0x80 == 0 {
				return (value, i + 1)
			}
			shift += 7
			if shift >= 64 { return (0, 0) }
		}
		return (0, 0)
	}

	private func encodeVarint(_ value: UInt64) -> [UInt8] {
		var result: [UInt8] = []
		var v = value
		repeat {
			var byte = UInt8(v & 0x7F)
			v >>= 7
			if v != 0 { byte |= 0x80 }
			result.append(byte)
		} while v != 0
		return result
	}
}

private extension Array where Element == UInt8 {
	func findSubarray(_ target: [UInt8]) -> Range<Int>? {
		guard target.count <= count else { return nil }
		for i in 0...(count - target.count) {
			if Array(self[i..<(i + target.count)]) == target {
				return i..<(i + target.count)
			}
		}
		return nil
	}
}
