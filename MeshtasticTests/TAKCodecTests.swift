import Foundation
import Testing

@testable import Meshtastic

// MARK: - FountainConstants

@Suite("FountainConstants")
struct FountainConstantsTests {

	@Test func magic_isFTN() {
		#expect(FountainConstants.magic == [0x46, 0x54, 0x4E])
	}

	@Test func blockSize_is220() {
		#expect(FountainConstants.blockSize == 220)
	}

	@Test func dataHeaderSize_is11() {
		#expect(FountainConstants.dataHeaderSize == 11)
	}

	@Test func fountainThreshold_is233() {
		#expect(FountainConstants.fountainThreshold == 233)
	}

	@Test func ackPacketSize_is19() {
		#expect(FountainConstants.ackPacketSize == 19)
	}
}

// MARK: - FountainBlock

@Suite("FountainBlock")
struct FountainBlockTests {

	@Test func copy_createsIndependentCopy() {
		let original = FountainBlock(seed: 42, indices: [0, 1, 2], payload: Data([1, 2, 3]))
		let copied = original.copy()
		#expect(copied.seed == original.seed)
		#expect(copied.indices == original.indices)
		#expect(copied.payload == original.payload)
	}
}

// MARK: - FountainReceiveState

@Suite("FountainReceiveState")
struct FountainReceiveStateTests {

	@Test func init_setsProperties() {
		let state = FountainReceiveState(transferId: 0x123, K: 5, totalLength: 1000)
		#expect(state.transferId == 0x123)
		#expect(state.K == 5)
		#expect(state.totalLength == 1000)
		#expect(state.blocks.isEmpty)
	}

	@Test func addBlock_appendsBlock() {
		let state = FountainReceiveState(transferId: 1, K: 3, totalLength: 100)
		let block = FountainBlock(seed: 1, indices: [0], payload: Data([1]))
		state.addBlock(block)
		#expect(state.blocks.count == 1)
	}

	@Test func addBlock_rejectsDuplicateSeeds() {
		let state = FountainReceiveState(transferId: 1, K: 3, totalLength: 100)
		let block1 = FountainBlock(seed: 42, indices: [0], payload: Data([1]))
		let block2 = FountainBlock(seed: 42, indices: [1], payload: Data([2]))
		state.addBlock(block1)
		state.addBlock(block2)
		#expect(state.blocks.count == 1) // Second should be rejected
	}

	@Test func addBlock_allowsDifferentSeeds() {
		let state = FountainReceiveState(transferId: 1, K: 3, totalLength: 100)
		state.addBlock(FountainBlock(seed: 1, indices: [0], payload: Data([1])))
		state.addBlock(FountainBlock(seed: 2, indices: [1], payload: Data([2])))
		state.addBlock(FountainBlock(seed: 3, indices: [2], payload: Data([3])))
		#expect(state.blocks.count == 3)
	}

	@Test func isExpired_newState_isFalse() {
		let state = FountainReceiveState(transferId: 1, K: 3, totalLength: 100)
		#expect(!state.isExpired)
	}
}

// MARK: - JavaRandom

@Suite("JavaRandom LCG")
struct JavaRandomTests {

	@Test func deterministicOutput_sameSeedSameResult() {
		var rng1 = JavaRandom(seed: 12345)
		var rng2 = JavaRandom(seed: 12345)
		#expect(rng1.nextInt(bound: 100) == rng2.nextInt(bound: 100))
		#expect(rng1.nextInt(bound: 100) == rng2.nextInt(bound: 100))
	}

	@Test func differentSeeds_differentResults() {
		var rng1 = JavaRandom(seed: 1)
		var rng2 = JavaRandom(seed: 2)
		// Different seeds should generally produce different output
		let a = rng1.nextInt(bound: 1000)
		let b = rng2.nextInt(bound: 1000)
		#expect(a != b)
	}

	@Test func nextInt_withinBound() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<100 {
			let val = rng.nextInt(bound: 10)
			#expect(val >= 0 && val < 10)
		}
	}

	@Test func nextInt_boundOne_alwaysZero() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<10 {
			#expect(rng.nextInt(bound: 1) == 0)
		}
	}

	@Test func nextInt_boundZero_returnsZero() {
		var rng = JavaRandom(seed: 42)
		#expect(rng.nextInt(bound: 0) == 0)
	}

	@Test func nextDouble_inRange() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<100 {
			let val = rng.nextDouble()
			#expect(val >= 0.0 && val < 1.0)
		}
	}

	@Test func nextBits_returnsValue() {
		var rng = JavaRandom(seed: 42)
		let bits = rng.next(bits: 16)
		#expect(bits >= 0)
	}

	@Test func powerOfTwo_bound_works() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<50 {
			let val = rng.nextInt(bound: 16) // power of 2
			#expect(val >= 0 && val < 16)
		}
	}
}

// MARK: - FountainCodec Static Methods

@Suite("FountainCodec Packet Detection")
struct FountainCodecDetectionTests {

	@Test func isFountainPacket_validMagic_returnsTrue() {
		var data = Data([0x46, 0x54, 0x4E]) // "FTN"
		data.append(Data(repeating: 0, count: 8))
		#expect(FountainCodec.isFountainPacket(data))
	}

	@Test func isFountainPacket_invalidMagic_returnsFalse() {
		let data = Data([0x00, 0x00, 0x00, 0x00])
		#expect(!FountainCodec.isFountainPacket(data))
	}

	@Test func isFountainPacket_tooShort_returnsFalse() {
		let data = Data([0x46, 0x54])
		#expect(!FountainCodec.isFountainPacket(data))
	}

	@Test func isFountainPacket_emptyData_returnsFalse() {
		#expect(!FountainCodec.isFountainPacket(Data()))
	}

	@Test func computeHash_returnsEightBytes() {
		let data = Data("Hello World".utf8)
		let hash = FountainCodec.computeHash(data)
		#expect(hash.count == 8)
	}

	@Test func computeHash_deterministic() {
		let data = Data("Test".utf8)
		let hash1 = FountainCodec.computeHash(data)
		let hash2 = FountainCodec.computeHash(data)
		#expect(hash1 == hash2)
	}

	@Test func computeHash_differentData_differentHash() {
		let hash1 = FountainCodec.computeHash(Data("A".utf8))
		let hash2 = FountainCodec.computeHash(Data("B".utf8))
		#expect(hash1 != hash2)
	}
}

// MARK: - FountainCodec Encode/Decode

@Suite("FountainCodec Encoding")
struct FountainCodecEncodingTests {

	@Test func encode_smallData_producesPackets() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0x42, count: 500)
		let transferId: UInt32 = 0x123456
		let packets = codec.encode(data: data, transferId: transferId)
		#expect(!packets.isEmpty)
	}

	@Test func encode_emptyData_returnsEmpty() {
		let codec = FountainCodec.shared
		let packets = codec.encode(data: Data(), transferId: 1)
		#expect(packets.isEmpty)
	}

	@Test func encode_packetsStartWithMagic() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0xAB, count: 300)
		let packets = codec.encode(data: data, transferId: 0x42)
		for packet in packets {
			#expect(packet[0] == 0x46) // 'F'
			#expect(packet[1] == 0x54) // 'T'
			#expect(packet[2] == 0x4E) // 'N'
		}
	}

	@Test func encode_singleBlock_producesPackets() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0x01, count: 100) // Small enough for 1 source block
		let packets = codec.encode(data: data, transferId: 0x1)
		#expect(packets.count >= 1)
	}

	@Test func parseDataHeader_validPacket_returnsHeader() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0x42, count: 500)
		let packets = codec.encode(data: data, transferId: 0xABCDEF)
		if let firstPacket = packets.first {
			let header = codec.parseDataHeader(firstPacket)
			#expect(header != nil)
			#expect(header?.transferId == 0xABCDEF)
		}
	}

	@Test func parseDataHeader_tooShort_returnsNil() {
		let codec = FountainCodec.shared
		let short = Data([0x46, 0x54, 0x4E, 0x00])
		#expect(codec.parseDataHeader(short) == nil)
	}

	@Test func parseDataHeader_wrongMagic_returnsNil() {
		let codec = FountainCodec.shared
		let bad = Data(repeating: 0, count: 20)
		#expect(codec.parseDataHeader(bad) == nil)
	}
}

// MARK: - FountainCodec ACK

@Suite("FountainCodec ACK")
struct FountainCodecAckTests {

	@Test func buildAck_correctSize() {
		let codec = FountainCodec.shared
		let hash = Data(repeating: 0xAA, count: 8)
		let ack = codec.buildAck(
			transferId: 0x123,
			type: FountainConstants.ackTypeComplete,
			received: 5,
			needed: 0,
			dataHash: hash
		)
		#expect(ack.count == FountainConstants.ackPacketSize)
	}

	@Test func buildAck_startsWithMagic() {
		let codec = FountainCodec.shared
		let hash = Data(repeating: 0, count: 8)
		let ack = codec.buildAck(transferId: 0, type: 0, received: 0, needed: 0, dataHash: hash)
		#expect(ack[0] == 0x46)
		#expect(ack[1] == 0x54)
		#expect(ack[2] == 0x4E)
	}

	@Test func parseAck_validData_returnsAck() {
		let codec = FountainCodec.shared
		let hash = Data(repeating: 0xBB, count: 8)
		let built = codec.buildAck(
			transferId: 0xABC,
			type: FountainConstants.ackTypeComplete,
			received: 10,
			needed: 2,
			dataHash: hash
		)
		let parsed = codec.parseAck(built)
		#expect(parsed != nil)
		#expect(parsed?.transferId == 0xABC)
		#expect(parsed?.type == FountainConstants.ackTypeComplete)
		#expect(parsed?.received == 10)
		#expect(parsed?.needed == 2)
	}

	@Test func parseAck_tooShort_returnsNil() {
		let codec = FountainCodec.shared
		#expect(codec.parseAck(Data([0x46, 0x54, 0x4E])) == nil)
	}

	@Test func parseAck_wrongMagic_returnsNil() {
		let codec = FountainCodec.shared
		let bad = Data(repeating: 0, count: 20)
		#expect(codec.parseAck(bad) == nil)
	}

	@Test func generateTransferId_is24Bit() {
		let codec = FountainCodec.shared
		for _ in 0..<10 {
			let id = codec.generateTransferId()
			#expect(id <= 0xFFFFFF)
		}
	}
}

// MARK: - EXICodec (Zlib)

@Suite("EXICodec Compression")
struct EXICodecTests {

	@Test func compress_validXML_returnsData() {
		let xml = "<event version='2.0'><point lat='37.0' lon='-122.0'/></event>"
		let compressed = EXICodec.shared.compress(xml)
		#expect(compressed != nil)
	}

	@Test func compress_startsWithZlibHeader() {
		let xml = "<event version='2.0'><point lat='37.0' lon='-122.0'/></event>"
		if let compressed = EXICodec.shared.compress(xml) {
			if compressed.count >= 2 {
				#expect(compressed[0] == 0x78) // Zlib magic byte
			}
		}
	}

	@Test func decompress_compressedData_returnsOriginal() {
		let original = "<event><detail><contact callsign='TEST'/></detail></event>"
		if let compressed = EXICodec.shared.compress(original) {
			let decompressed = EXICodec.shared.decompress(compressed)
			#expect(decompressed == original)
		}
	}

	@Test func decompress_rawUTF8_returnsString() {
		let xml = "<simple>text</simple>"
		let data = Data(xml.utf8)
		let result = EXICodec.shared.decompress(data)
		#expect(result == xml)
	}

	@Test func decompress_invalidData_returnsNilOrFallback() {
		let garbage = Data([0xFF, 0xFE, 0xFD, 0xFC])
		// Should either return nil or handle gracefully
		_ = EXICodec.shared.decompress(garbage)
	}

	@Test func roundTrip_longString() {
		let longXml = String(repeating: "<tag>content</tag>", count: 100)
		if let compressed = EXICodec.shared.compress(longXml) {
			#expect(compressed.count < longXml.utf8.count) // Should actually compress
			let decompressed = EXICodec.shared.decompress(compressed)
			#expect(decompressed == longXml)
		}
	}

	@Test func compress_emptyString_returnsData() {
		let compressed = EXICodec.shared.compress("")
		// Empty string should still produce some zlib output
		#expect(compressed != nil)
	}
}
