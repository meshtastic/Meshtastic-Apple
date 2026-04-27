import Foundation
import Testing

@testable import Meshtastic

// MARK: - FountainConstants

@Suite("FountainConstants Extended")
struct FountainConstantsExtendedTests {

	@Test func magic_bytes() {
		#expect(FountainConstants.magic == [0x46, 0x54, 0x4E])
	}

	@Test func blockSize() {
		#expect(FountainConstants.blockSize == 220)
	}

	@Test func dataHeaderSize() {
		#expect(FountainConstants.dataHeaderSize == 11)
	}

	@Test func fountainThreshold() {
		#expect(FountainConstants.fountainThreshold == 233)
	}

	@Test func transferTypes() {
		#expect(FountainConstants.transferTypeCot == 0x00)
		#expect(FountainConstants.transferTypeFile == 0x01)
	}

	@Test func ackTypes() {
		#expect(FountainConstants.ackTypeComplete == 0x02)
		#expect(FountainConstants.ackTypeNeedMore == 0x03)
	}

	@Test func ackPacketSize() {
		#expect(FountainConstants.ackPacketSize == 19)
	}
}

// MARK: - FountainBlock

@Suite("FountainBlock Extended")
struct FountainBlockExtendedTests {

	@Test func copy_createsIndependentCopy() {
		let block = FountainBlock(seed: 42, indices: [0, 1, 2], payload: Data([1, 2, 3]))
		let blockCopy = block.copy()
		#expect(blockCopy.seed == 42)
		#expect(blockCopy.indices == [0, 1, 2])
		#expect(blockCopy.payload == Data([1, 2, 3]))
	}

	@Test func init_setsProperties() {
		let block = FountainBlock(seed: 100, indices: [5], payload: Data())
		#expect(block.seed == 100)
		#expect(block.indices == [5])
		#expect(block.payload.isEmpty)
	}
}

// MARK: - FountainReceiveState

@Suite("FountainReceiveState Extended")
struct FountainReceiveStateExtendedTests {

	@Test func init_setsProperties() {
		let state = FountainReceiveState(transferId: 12345, K: 3, totalLength: 500)
		#expect(state.transferId == 12345)
		#expect(state.K == 3)
		#expect(state.totalLength == 500)
		#expect(state.blocks.isEmpty)
	}

	@Test func addBlock_addsUniqueBlock() {
		let state = FountainReceiveState(transferId: 1, K: 2, totalLength: 100)
		let block1 = FountainBlock(seed: 1, indices: [0], payload: Data([1]))
		let block2 = FountainBlock(seed: 2, indices: [1], payload: Data([2]))
		state.addBlock(block1)
		state.addBlock(block2)
		#expect(state.blocks.count == 2)
	}

	@Test func addBlock_rejectsDuplicate() {
		let state = FountainReceiveState(transferId: 1, K: 2, totalLength: 100)
		let block = FountainBlock(seed: 1, indices: [0], payload: Data([1]))
		state.addBlock(block)
		state.addBlock(block)
		#expect(state.blocks.count == 1)
	}

	@Test func isExpired_falseWhenNew() {
		let state = FountainReceiveState(transferId: 1, K: 1, totalLength: 10)
		#expect(!state.isExpired)
	}
}

// MARK: - JavaRandom

@Suite("JavaRandom Extended")
struct JavaRandomExtendedTests {

	@Test func deterministic_sequence() {
		var rng1 = JavaRandom(seed: 42)
		var rng2 = JavaRandom(seed: 42)
		// Same seed should produce same sequence
		for _ in 0..<10 {
			#expect(rng1.next(bits: 32) == rng2.next(bits: 32))
		}
	}

	@Test func nextInt_bound() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<100 {
			let val = rng.nextInt(bound: 10)
			#expect(val >= 0 && val < 10)
		}
	}

	@Test func nextInt_zeroBound_returnsZero() {
		var rng = JavaRandom(seed: 42)
		#expect(rng.nextInt(bound: 0) == 0)
	}

	@Test func nextInt_powerOfTwo() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<50 {
			let val = rng.nextInt(bound: 8)
			#expect(val >= 0 && val < 8)
		}
	}

	@Test func nextDouble_range() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<100 {
			let val = rng.nextDouble()
			#expect(val >= 0.0 && val < 1.0)
		}
	}

	@Test func differentSeeds_differentSequences() {
		var rng1 = JavaRandom(seed: 42)
		var rng2 = JavaRandom(seed: 99)
		var same = true
		for _ in 0..<10 {
			if rng1.next(bits: 32) != rng2.next(bits: 32) {
				same = false
				break
			}
		}
		#expect(!same)
	}

	@Test func next_bits31() {
		var rng = JavaRandom(seed: 42)
		let val = rng.next(bits: 31)
		#expect(val >= 0)
	}

	@Test func nextInt_bound1_alwaysZero() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<10 {
			#expect(rng.nextInt(bound: 1) == 0)
		}
	}
}

// MARK: - FountainCodec Static Methods

@Suite("FountainCodec isFountainPacket")
struct FountainCodecStaticTests {

	@Test func isFountainPacket_validMagic() {
		let data = Data([0x46, 0x54, 0x4E, 0x00, 0x00, 0x00])
		#expect(FountainCodec.isFountainPacket(data))
	}

	@Test func isFountainPacket_invalidMagic() {
		let data = Data([0x00, 0x00, 0x00, 0x00])
		#expect(!FountainCodec.isFountainPacket(data))
	}

	@Test func isFountainPacket_tooShort() {
		let data = Data([0x46, 0x54])
		#expect(!FountainCodec.isFountainPacket(data))
	}

	@Test func isFountainPacket_empty() {
		#expect(!FountainCodec.isFountainPacket(Data()))
	}

	@Test func computeHash_returnsSHA256Prefix() {
		let data = Data("Hello, World!".utf8)
		let hash = FountainCodec.computeHash(data)
		#expect(hash.count == 8)
	}

	@Test func computeHash_deterministic() {
		let data = Data("test".utf8)
		let hash1 = FountainCodec.computeHash(data)
		let hash2 = FountainCodec.computeHash(data)
		#expect(hash1 == hash2)
	}

	@Test func computeHash_differentInput_differentHash() {
		let hash1 = FountainCodec.computeHash(Data("abc".utf8))
		let hash2 = FountainCodec.computeHash(Data("def".utf8))
		#expect(hash1 != hash2)
	}
}

// MARK: - FountainCodec Instance Methods

@Suite("FountainCodec Instance")
struct FountainCodecInstanceTests {

	@Test func generateTransferId_is24bit() {
		let codec = FountainCodec.shared
		let id = codec.generateTransferId()
		#expect(id <= 0xFFFFFF)
	}

	@Test func generateTransferId_unique() {
		let codec = FountainCodec.shared
		let ids = (0..<10).map { _ in codec.generateTransferId() }
		let uniqueIds = Set(ids)
		// With 24-bit random IDs, 10 should all be unique
		#expect(uniqueIds.count == 10)
	}

	@Test func parseDataHeader_validPacket() {
		let codec = FountainCodec.shared
		// Build a valid packet header: magic(3) + transferId(3) + seed(2) + K(1) + totalLength(2)
		var data = Data()
		data.append(contentsOf: FountainConstants.magic) // Magic
		data.append(contentsOf: [0x00, 0x01, 0x02])     // Transfer ID = 258
		data.append(contentsOf: [0x00, 0x0A])            // Seed = 10
		data.append(0x03)                                  // K = 3
		data.append(contentsOf: [0x01, 0xF4])            // Total Length = 500
		// Add some payload padding to meet minimum
		data.append(Data(repeating: 0, count: 220))

		let header = codec.parseDataHeader(data)
		#expect(header != nil)
		#expect(header?.transferId == 258)
		#expect(header?.seed == 10)
		#expect(header?.K == 3)
		#expect(header?.totalLength == 500)
	}

	@Test func parseDataHeader_invalidMagic_returnsNil() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0, count: 20)
		#expect(codec.parseDataHeader(data) == nil)
	}

	@Test func parseDataHeader_tooShort_returnsNil() {
		let codec = FountainCodec.shared
		var data = Data()
		data.append(contentsOf: FountainConstants.magic)
		data.append(contentsOf: [0x00, 0x01, 0x02])
		// Only 6 bytes, need 11
		#expect(codec.parseDataHeader(data) == nil)
	}

	@Test func encode_emptyData_returnsEmpty() {
		let codec = FountainCodec.shared
		let result = codec.encode(data: Data(), transferId: 1)
		#expect(result.isEmpty)
	}

	@Test func encode_smallData_producesPackets() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0xAA, count: 100)
		let packets = codec.encode(data: data, transferId: 42)
		#expect(!packets.isEmpty)
		// All packets should start with fountain magic
		for packet in packets {
			#expect(FountainCodec.isFountainPacket(packet))
		}
	}

	@Test func encode_largerData_producesMorePackets() {
		let codec = FountainCodec.shared
		let smallData = Data(repeating: 0xAA, count: 100)
		let largeData = Data(repeating: 0xBB, count: 1000)
		let smallPackets = codec.encode(data: smallData, transferId: 1)
		let largePackets = codec.encode(data: largeData, transferId: 2)
		#expect(largePackets.count > smallPackets.count)
	}

	@Test func encode_decode_roundTrip() {
		let codec = FountainCodec.shared
		let originalData = Data("Hello, Fountain Codes!".utf8)
		let transferId: UInt32 = 12345
		let packets = codec.encode(data: originalData, transferId: transferId)

		// Feed all packets to the decoder
		var decoded: Data?
		for packet in packets {
			if let result = codec.handleIncomingPacket(packet, senderNodeId: 1) {
				decoded = result.data
				#expect(result.transferId == transferId)
				break
			}
		}

		#expect(decoded == originalData)
	}

	@Test func buildAck_correctSize() {
		let codec = FountainCodec.shared
		let hash = Data(repeating: 0xAA, count: 8)
		let ack = codec.buildAck(
			transferId: 100,
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
		#expect(FountainCodec.isFountainPacket(ack))
	}

	@Test func parseAck_validPacket() {
		let codec = FountainCodec.shared
		let hash = Data([1, 2, 3, 4, 5, 6, 7, 8])
		let ack = codec.buildAck(
			transferId: 0x010203,
			type: FountainConstants.ackTypeNeedMore,
			received: 3,
			needed: 2,
			dataHash: hash
		)
		let parsed = codec.parseAck(ack)
		#expect(parsed != nil)
		#expect(parsed?.transferId == 0x010203)
		#expect(parsed?.type == FountainConstants.ackTypeNeedMore)
		#expect(parsed?.received == 3)
		#expect(parsed?.needed == 2)
		#expect(parsed?.dataHash == hash)
	}

	@Test func parseAck_tooShort_returnsNil() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0, count: 5)
		#expect(codec.parseAck(data) == nil)
	}

	@Test func parseAck_invalidMagic_returnsNil() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0, count: 19)
		#expect(codec.parseAck(data) == nil)
	}

	@Test func handleIncomingPacket_invalidPacket_returnsNil() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0, count: 50)
		#expect(codec.handleIncomingPacket(data, senderNodeId: 1) == nil)
	}

	@Test func handleIncomingPacket_invalidPayloadSize_returnsNil() {
		let codec = FountainCodec.shared
		// Valid header but wrong payload size
		var data = Data()
		data.append(contentsOf: FountainConstants.magic)
		data.append(contentsOf: [0x00, 0x01, 0x02])
		data.append(contentsOf: [0x00, 0x0A])
		data.append(0x03)
		data.append(contentsOf: [0x01, 0xF4])
		data.append(Data(repeating: 0, count: 10)) // Wrong size, should be 220
		#expect(codec.handleIncomingPacket(data, senderNodeId: 1) == nil)
	}
}
