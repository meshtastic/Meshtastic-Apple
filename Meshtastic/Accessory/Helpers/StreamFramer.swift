//
//  StreamFramer.swift
//  Meshtastic
//
//  Created by Ben Meadors on 8/3/26.
//

import Foundation

/// Frames and de-frames the Meshtastic stream protocol used over serial/USB links:
/// `[0x94, 0xC3, lengthHigh, lengthLow, payload...]` where the length is a
/// big-endian UInt16 count of payload bytes.
///
/// Pure logic, no platform dependencies and no logging — policy (what to do with
/// each payload, when to log) stays at the call sites. The framer is garbage
/// tolerant: bytes before a start-of-frame marker are discarded, and a corrupted
/// header length larger than ``maxPayloadLength`` causes a resync (drop the first
/// magic byte and rescan) instead of stalling while waiting for bytes that will
/// never arrive.
struct StreamFramer {

	/// The two-byte marker that begins every frame.
	static let startOfFrame: [UInt8] = [0x94, 0xC3]

	/// MAX_TO_FROM_RADIO_SIZE: any header advertising a longer payload is corruption.
	static let maxPayloadLength = 512

	/// Repeated START2 bytes sent to wake a device's serial console before framed traffic.
	static let wakeSequence = Data(repeating: 0xC3, count: 32)

	private var buffer = Data()

	/// Appends a chunk of raw stream bytes and returns every complete payload now available.
	///
	/// Incomplete trailing frames are retained until subsequent chunks complete them,
	/// including a start-of-frame marker split across chunk boundaries.
	mutating func append(_ chunk: Data) -> [Data] {
		buffer.append(chunk)
		var payloads: [Data] = []

		while !buffer.isEmpty {
			// Find the start-of-frame marker; everything before it is garbage.
			guard let magicRange = buffer.firstRange(of: Self.startOfFrame) else {
				// Keep a trailing first magic byte: its partner may arrive in the next chunk.
				if buffer.last == Self.startOfFrame[0] {
					buffer = Data(buffer.suffix(1))
				} else {
					buffer.removeAll(keepingCapacity: true)
				}
				break
			}
			if magicRange.lowerBound > buffer.startIndex {
				buffer.removeSubrange(buffer.startIndex..<magicRange.lowerBound)
			}

			// Wait for the full 4-byte header before reading the length.
			guard buffer.count >= 4 else { break }

			// Data subranges keep their parent's indices, so stay startIndex-relative.
			let lengthHigh = Int(buffer[buffer.startIndex + 2])
			let lengthLow = Int(buffer[buffer.startIndex + 3])
			let length = (lengthHigh << 8) | lengthLow

			// A length beyond the protocol maximum means the header is corrupt:
			// drop the first magic byte and rescan rather than waiting forever.
			if length > Self.maxPayloadLength {
				buffer.removeFirst()
				continue
			}

			let totalFrameLength = Self.startOfFrame.count + 2 + length
			guard buffer.count >= totalFrameLength else { break }

			let payloadStart = buffer.startIndex + 4
			let payloadEnd = buffer.startIndex + totalFrameLength
			payloads.append(Data(buffer[payloadStart..<payloadEnd]))
			buffer.removeSubrange(buffer.startIndex..<payloadEnd)
		}

		return payloads
	}

	/// Discards all buffered bytes, returning the framer to its initial state.
	mutating func reset() {
		buffer.removeAll()
	}

	/// Wraps a payload in a start-of-frame header with a big-endian UInt16 length.
	static func encode(_ payload: Data) -> Data {
		let length = UInt16(payload.count)
		var frame = Data(capacity: payload.count + 4)
		frame.append(contentsOf: startOfFrame)
		frame.append(UInt8(length >> 8))
		frame.append(UInt8(length & 0xFF))
		frame.append(payload)
		return frame
	}
}
