//
//  StreamFramerTests.swift
//  MeshtasticTests
//
//  Created by Ben Meadors on 8/3/26.
//
//  Exercises the Meshtastic stream framing (0x94 0xC3 + big-endian UInt16 length + payload):
//  chunk reassembly, garbage tolerance, and resync after a corrupted length header.
//

import Foundation
import Testing
@testable import Meshtastic

@Suite("StreamFramer")
struct StreamFramerTests {

	// MARK: - Helpers

	private func makePayload(_ bytes: [UInt8]) -> Data {
		Data(bytes)
	}

	private func makeFrame(_ payload: [UInt8]) -> Data {
		StreamFramer.encode(Data(payload))
	}

	// MARK: - Basic framing

	@Test func wholeFrameInOneChunk() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0x01, 0x02, 0x03, 0x04]
		let results = framer.append(makeFrame(payload))
		#expect(results == [makePayload(payload)])
	}

	@Test func frameSplitAcrossTwoChunks() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
		let frame = makeFrame(payload)

		// Split mid-payload.
		let first = framer.append(frame.prefix(6))
		#expect(first.isEmpty)
		let second = framer.append(frame.suffix(from: 6))
		#expect(second == [makePayload(payload)])
	}

	@Test func frameSplitAcrossThreeChunksIncludingMidHeader() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0x10, 0x20, 0x30]
		let frame = makeFrame(payload)

		// Chunk 1 is just the first magic byte, chunk 2 splits the length field.
		#expect(framer.append(frame.prefix(1)).isEmpty)
		#expect(framer.append(frame.subdata(in: 1..<3)).isEmpty)
		let final = framer.append(frame.suffix(from: 3))
		#expect(final == [makePayload(payload)])
	}

	@Test func multipleFramesInOneChunk() {
		var framer = StreamFramer()
		let payloadA: [UInt8] = [0x01]
		let payloadB: [UInt8] = [0x02, 0x03]
		let payloadC: [UInt8] = [0x04, 0x05, 0x06]
		var chunk = makeFrame(payloadA)
		chunk.append(makeFrame(payloadB))
		chunk.append(makeFrame(payloadC))

		let results = framer.append(chunk)
		#expect(results == [makePayload(payloadA), makePayload(payloadB), makePayload(payloadC)])
	}

	// MARK: - Garbage tolerance

	@Test func leadingGarbageBeforeMagic() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0x42, 0x43]
		var chunk = Data([0x00, 0xFF, 0x13, 0x37])
		chunk.append(makeFrame(payload))

		let results = framer.append(chunk)
		#expect(results == [makePayload(payload)])
	}

	@Test func garbageBetweenFrames() {
		var framer = StreamFramer()
		let payloadA: [UInt8] = [0x11]
		let payloadB: [UInt8] = [0x22]
		var chunk = makeFrame(payloadA)
		chunk.append(Data([0xDE, 0xAD, 0xBE, 0xEF]))
		chunk.append(makeFrame(payloadB))

		let results = framer.append(chunk)
		#expect(results == [makePayload(payloadA), makePayload(payloadB)])
	}

	@Test func interleavedASCIIDebugLogBytes() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0x08, 0x01]
		var chunk = Data("INFO  | ??:??:?? 1 Booting radio\r\n".utf8)
		chunk.append(makeFrame(payload))
		chunk.append(Data("DEBUG | Sending packet\r\n".utf8))

		let results = framer.append(chunk)
		#expect(results == [makePayload(payload)])

		// The trailing ASCII must not corrupt a subsequent frame.
		let next = framer.append(makeFrame(payload))
		#expect(next == [makePayload(payload)])
	}

	@Test func loneMagicByteWithoutSecondByte() {
		var framer = StreamFramer()
		// 0x94 followed by a byte that is not 0xC3 is not a frame start.
		#expect(framer.append(Data([0x94])).isEmpty)
		#expect(framer.append(Data([0x00, 0x01, 0x02])).isEmpty)

		// The framer must still parse a real frame afterwards.
		let payload: [UInt8] = [0x55]
		let results = framer.append(makeFrame(payload))
		#expect(results == [makePayload(payload)])
	}

	@Test func magicSplitAcrossChunkBoundary() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0x77, 0x88]
		let frame = makeFrame(payload)

		// Garbage, then 0x94 at the end of a chunk; 0xC3 arrives with the next chunk.
		var first = Data([0x01, 0x02])
		first.append(frame.prefix(1))
		#expect(framer.append(first).isEmpty)
		let results = framer.append(frame.suffix(from: 1))
		#expect(results == [makePayload(payload)])
	}

	// MARK: - Corrupted length header (resync)

	@Test func corruptLengthOver512FollowedByValidFrameInSameChunk() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0x99, 0x9A]
		// 0x0FA0 = 4000 > 512: corrupt header that previously stalled the parser.
		var chunk = Data([0x94, 0xC3, 0x0F, 0xA0])
		chunk.append(makeFrame(payload))

		let results = framer.append(chunk)
		#expect(results == [makePayload(payload)])
	}

	@Test func corruptLengthOver512FollowedByValidFrameInLaterChunk() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0x99]
		#expect(framer.append(Data([0x94, 0xC3, 0xFF, 0xFF])).isEmpty)
		let results = framer.append(makeFrame(payload))
		#expect(results == [makePayload(payload)])
	}

	@Test func corruptHeaderOverlappingRealMagic() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0x42]
		// The bogus header's length bytes are themselves 0x94 0xC3 (= 38083 > 512):
		// resync must discard one byte and find the real frame that overlaps it.
		var chunk = Data([0x94, 0xC3])
		chunk.append(makeFrame(payload))

		let results = framer.append(chunk)
		#expect(results == [makePayload(payload)])
	}

	// MARK: - Length boundaries

	@Test func lengthExactly512Accepted() {
		var framer = StreamFramer()
		let payload = [UInt8](repeating: 0x5A, count: StreamFramer.maxPayloadLength)
		let results = framer.append(makeFrame(payload))
		#expect(results.count == 1)
		#expect(results.first == makePayload(payload))
	}

	@Test func emptyPayloadFrame() {
		var framer = StreamFramer()
		let results = framer.append(Data([0x94, 0xC3, 0x00, 0x00]))
		#expect(results == [Data()])
	}

	// MARK: - Encoding

	@Test func encodeProducesHeaderAndBigEndianLength() {
		let encoded = StreamFramer.encode(Data([UInt8](repeating: 0x00, count: 0x0203)))
		#expect(Array(encoded.prefix(4)) == [0x94, 0xC3, 0x02, 0x03])
		#expect(encoded.count == 4 + 0x0203)
	}

	@Test func encodeRoundTripsThroughAppend() {
		var framer = StreamFramer()
		let payload = Data((0..<300).map { UInt8($0 % 256) })
		let results = framer.append(StreamFramer.encode(payload))
		#expect(results == [payload])
	}

	// MARK: - Constants and state

	@Test func wakeSequenceIs32BytesOfC3() {
		#expect(StreamFramer.wakeSequence.count == 32)
		#expect(StreamFramer.wakeSequence.allSatisfy { $0 == 0xC3 })
	}

	@Test func resetClearsBufferedState() {
		var framer = StreamFramer()
		let payload: [UInt8] = [0x01, 0x02]
		let frame = makeFrame(payload)

		// Buffer a partial frame, then reset: the remainder must not complete it.
		#expect(framer.append(frame.prefix(4)).isEmpty)
		framer.reset()
		#expect(framer.append(frame.suffix(from: 4)).isEmpty)

		// A fresh complete frame still parses.
		let results = framer.append(frame)
		#expect(results == [makePayload(payload)])
	}
}
