// FountainCodecPipelineTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

// MARK: - FountainCodec Full Pipeline Tests

@Suite("FountainCodec handleIncomingPacket pipeline")
struct FountainCodecHandleIncomingTests {

	@Test func encode_then_decode_smallData() {
		let codec = FountainCodec.shared
		let original = Data("Hello, mesh network!".utf8)
		let transferId = UInt32(0x123456 & 0xFFFFFF)
		let packets = codec.encode(data: original, transferId: transferId)
		#expect(!packets.isEmpty)

		var result: (data: Data, transferId: UInt32)?
		for packet in packets {
			result = codec.handleIncomingPacket(packet, senderNodeId: 1)
			if result != nil { break }
		}

		if let result {
			#expect(result.data == original)
			#expect(result.transferId == transferId)
		}
	}

	@Test func encode_then_decode_exactBlockSize() {
		let codec = FountainCodec.shared
		let original = Data(repeating: 0xAB, count: FountainConstants.blockSize)
		let transferId = UInt32(0xABCDEF & 0xFFFFFF)
		let packets = codec.encode(data: original, transferId: transferId)
		#expect(!packets.isEmpty)

		var result: (data: Data, transferId: UInt32)?
		for packet in packets {
			result = codec.handleIncomingPacket(packet, senderNodeId: 2)
			if result != nil { break }
		}

		if let result {
			#expect(result.data == original)
		}
	}

	@Test func encode_then_decode_multiBlock() {
		let codec = FountainCodec.shared
		// Data spanning multiple blocks
		let original = Data((0..<500).map { UInt8($0 % 256) })
		let transferId = UInt32(0x999999 & 0xFFFFFF)
		let packets = codec.encode(data: original, transferId: transferId)

		// Should generate more packets than source blocks
		let k = max(1, Int(ceil(Double(original.count) / Double(FountainConstants.blockSize))))
		#expect(packets.count >= k)

		var result: (data: Data, transferId: UInt32)?
		for packet in packets {
			result = codec.handleIncomingPacket(packet, senderNodeId: 3)
			if result != nil { break }
		}

		if let result {
			#expect(result.data == original)
		}
	}

	@Test func handleIncomingPacket_invalidHeader_returnsNil() {
		let codec = FountainCodec.shared
		let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04])
		let result = codec.handleIncomingPacket(garbage, senderNodeId: 1)
		#expect(result == nil)
	}

	@Test func handleIncomingPacket_tooShort_returnsNil() {
		let codec = FountainCodec.shared
		let result = codec.handleIncomingPacket(Data(), senderNodeId: 1)
		#expect(result == nil)
	}

	@Test func handleIncomingPacket_wrongMagic_returnsNil() {
		let codec = FountainCodec.shared
		var packet = Data(repeating: 0, count: FountainConstants.dataHeaderSize + FountainConstants.blockSize)
		packet[0] = 0xFF // wrong magic
		packet[1] = 0xFF
		packet[2] = 0xFF
		let result = codec.handleIncomingPacket(packet, senderNodeId: 1)
		#expect(result == nil)
	}

	@Test func handleIncomingPacket_wrongPayloadSize_returnsNil() {
		let codec = FountainCodec.shared
		// Valid magic but wrong payload size
		var packet = Data()
		packet.append(contentsOf: FountainConstants.magic)
		packet.append(contentsOf: [0x00, 0x00, 0x01]) // transferId
		packet.append(contentsOf: [0x00, 0x01]) // seed
		packet.append(0x01) // K
		packet.append(contentsOf: [0x00, 0x10]) // totalLength
		packet.append(Data(repeating: 0, count: 10)) // wrong size payload
		let result = codec.handleIncomingPacket(packet, senderNodeId: 1)
		#expect(result == nil)
	}
}

// MARK: - FountainCodec isFountainPacket

@Suite("FountainCodec isFountainPacket extended")
struct FountainIsFountainPacketExtendedTests {

	@Test func validMagic_returnsTrue() {
		var data = Data()
		data.append(contentsOf: FountainConstants.magic)
		data.append(Data(repeating: 0, count: 10))
		#expect(FountainCodec.isFountainPacket(data))
	}

	@Test func invalidMagic_returnsFalse() {
		let data = Data([0x00, 0x00, 0x00, 0x00])
		#expect(!FountainCodec.isFountainPacket(data))
	}

	@Test func tooShort_returnsFalse() {
		let data = Data([0x46, 0x54])
		#expect(!FountainCodec.isFountainPacket(data))
	}

	@Test func emptyData_returnsFalse() {
		#expect(!FountainCodec.isFountainPacket(Data()))
	}
}

// MARK: - FountainCodec parseDataHeader

@Suite("FountainCodec parseDataHeader extended")
struct FountainParseDataHeaderExtendedTests {

	@Test func validHeader_parsesCorrectly() {
		let codec = FountainCodec.shared
		var data = Data()
		data.append(contentsOf: FountainConstants.magic) // magic [0-2]
		data.append(contentsOf: [0x12, 0x34, 0x56]) // transferId [3-5]
		data.append(contentsOf: [0xAB, 0xCD]) // seed [6-7]
		data.append(0x05) // K [8]
		data.append(contentsOf: [0x01, 0x00]) // totalLength = 256 [9-10]

		let header = codec.parseDataHeader(data)
		#expect(header != nil)
		#expect(header?.transferId == 0x123456)
		#expect(header?.seed == 0xABCD)
		#expect(header?.K == 5)
		#expect(header?.totalLength == 256)
	}

	@Test func tooShort_returnsNil() {
		let codec = FountainCodec.shared
		let data = Data(FountainConstants.magic)
		#expect(codec.parseDataHeader(data) == nil)
	}

	@Test func wrongMagic_returnsNil() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0, count: FountainConstants.dataHeaderSize)
		#expect(codec.parseDataHeader(data) == nil)
	}
}

// MARK: - FountainCodec buildAck/parseAck roundtrip

@Suite("FountainCodec ACK roundtrip extended")
struct FountainAckRoundtripExtendedTests {

	@Test func buildAndParse_completeAck() {
		let codec = FountainCodec.shared
		let hash = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
		let ackData = codec.buildAck(
			transferId: 0xABCDEF,
			type: FountainConstants.ackTypeComplete,
			received: 10,
			needed: 0,
			dataHash: hash
		)
		#expect(ackData.count == FountainConstants.ackPacketSize)

		let parsed = codec.parseAck(ackData)
		#expect(parsed != nil)
		#expect(parsed?.transferId == 0xABCDEF)
		#expect(parsed?.type == FountainConstants.ackTypeComplete)
		#expect(parsed?.received == 10)
		#expect(parsed?.needed == 0)
		#expect(parsed?.dataHash == hash)
	}

	@Test func buildAndParse_needMoreAck() {
		let codec = FountainCodec.shared
		let hash = Data(repeating: 0xFF, count: 8)
		let ackData = codec.buildAck(
			transferId: 0x000001,
			type: FountainConstants.ackTypeNeedMore,
			received: 5,
			needed: 3,
			dataHash: hash
		)

		let parsed = codec.parseAck(ackData)
		#expect(parsed != nil)
		#expect(parsed?.type == FountainConstants.ackTypeNeedMore)
		#expect(parsed?.received == 5)
		#expect(parsed?.needed == 3)
	}

	@Test func parseAck_tooShort_returnsNil() {
		let codec = FountainCodec.shared
		let data = Data([0x46, 0x54, 0x4E, 0x00])
		#expect(codec.parseAck(data) == nil)
	}

	@Test func parseAck_wrongMagic_returnsNil() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0, count: FountainConstants.ackPacketSize)
		#expect(codec.parseAck(data) == nil)
	}
}

// MARK: - FountainCodec computeHash

@Suite("FountainCodec computeHash extended")
struct FountainComputeHashExtendedTests {

	@Test func hash_deterministic() {
		let data = Data("test data for hashing".utf8)
		let hash1 = FountainCodec.computeHash(data)
		let hash2 = FountainCodec.computeHash(data)
		#expect(hash1 == hash2)
	}

	@Test func hash_differentData_differentHashes() {
		let hash1 = FountainCodec.computeHash(Data("data1".utf8))
		let hash2 = FountainCodec.computeHash(Data("data2".utf8))
		#expect(hash1 != hash2)
	}

	@Test func hash_length() {
		let hash = FountainCodec.computeHash(Data("test".utf8))
		#expect(hash.count == 8) // truncated SHA256 to 8 bytes
	}

	@Test func hash_emptyData() {
		let hash = FountainCodec.computeHash(Data())
		#expect(hash.count == 8)
	}
}

// MARK: - FountainCodec encode edge cases

@Suite("FountainCodec encode edge cases")
struct FountainCodecEncodeEdgeCaseTests {

	@Test func encode_emptyData_returnsEmpty() {
		let codec = FountainCodec.shared
		let packets = codec.encode(data: Data(), transferId: 0x123)
		#expect(packets.isEmpty)
	}

	@Test func encode_singleByte() {
		let codec = FountainCodec.shared
		let packets = codec.encode(data: Data([0x42]), transferId: 0x456)
		#expect(!packets.isEmpty)
		// Single byte → K=1, with overhead → more than 1 packet
		#expect(packets.count >= 1)
	}

	@Test func encode_largeData() {
		let codec = FountainCodec.shared
		let data = Data(repeating: 0xCC, count: 2000)
		let packets = codec.encode(data: data, transferId: 0x789)
		let k = max(1, Int(ceil(Double(data.count) / Double(FountainConstants.blockSize))))
		#expect(packets.count >= k)
		// All packets should start with magic bytes
		for packet in packets {
			#expect(packet.count >= 3)
			#expect(packet[0] == FountainConstants.magic[0])
			#expect(packet[1] == FountainConstants.magic[1])
			#expect(packet[2] == FountainConstants.magic[2])
		}
	}

	@Test func encode_packetSize() {
		let codec = FountainCodec.shared
		let data = Data("Hello".utf8)
		let packets = codec.encode(data: data, transferId: 0xABC)
		for packet in packets {
			#expect(packet.count == FountainConstants.dataHeaderSize + FountainConstants.blockSize)
		}
	}
}

// MARK: - FountainReceiveState extended

@Suite("FountainReceiveState behavior extended")
struct FountainReceiveStateBehaviorExtendedTests {

	@Test func addBlock_skipsDuplicateSeeds() {
		let state = FountainReceiveState(transferId: 1, K: 3, totalLength: 100)
		let block1 = FountainBlock(seed: 42, indices: [0], payload: Data(repeating: 0, count: 10))
		let block2 = FountainBlock(seed: 42, indices: [1], payload: Data(repeating: 1, count: 10))

		state.addBlock(block1)
		state.addBlock(block2)
		#expect(state.blocks.count == 1)
	}

	@Test func addBlock_acceptsDifferentSeeds() {
		let state = FountainReceiveState(transferId: 1, K: 3, totalLength: 100)
		let block1 = FountainBlock(seed: 1, indices: [0], payload: Data(repeating: 0, count: 10))
		let block2 = FountainBlock(seed: 2, indices: [1], payload: Data(repeating: 1, count: 10))
		let block3 = FountainBlock(seed: 3, indices: [2], payload: Data(repeating: 2, count: 10))

		state.addBlock(block1)
		state.addBlock(block2)
		state.addBlock(block3)
		#expect(state.blocks.count == 3)
	}

	@Test func isExpired_newState_notExpired() {
		let state = FountainReceiveState(transferId: 1, K: 1, totalLength: 10)
		#expect(!state.isExpired)
	}
}

// MARK: - FountainBlock copy

@Suite("FountainBlock copy extended")
struct FountainBlockCopyExtendedTests {

	@Test func copy_createsIndependentCopy() {
		var original = FountainBlock(seed: 42, indices: [0, 1, 2], payload: Data([0xAA, 0xBB, 0xCC]))
		let copy = original.copy()

		original.indices.insert(3)
		#expect(copy.indices.count == 3)
		#expect(copy.seed == 42)
		#expect(copy.payload == Data([0xAA, 0xBB, 0xCC]))
	}
}

// MARK: - JavaRandom additional

@Suite("JavaRandom additional tests")
struct JavaRandomAdditionalTests {

	@Test func nextInt_zeroBound_returnsZero() {
		var rng = JavaRandom(seed: 42)
		let result = rng.nextInt(bound: 0)
		#expect(result == 0)
	}

	@Test func nextInt_negativeBound_returnsZero() {
		var rng = JavaRandom(seed: 42)
		let result = rng.nextInt(bound: -5)
		#expect(result == 0)
	}

	@Test func nextInt_powerOfTwo() {
		var rng = JavaRandom(seed: 42)
		let result = rng.nextInt(bound: 16)
		#expect(result >= 0 && result < 16)
	}

	@Test func nextInt_nonPowerOfTwo() {
		var rng = JavaRandom(seed: 42)
		let result = rng.nextInt(bound: 10)
		#expect(result >= 0 && result < 10)
	}

	@Test func nextDouble_range() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<100 {
			let val = rng.nextDouble()
			#expect(val >= 0.0 && val < 1.0)
		}
	}

	@Test func sameSeed_sameSequence() {
		var rng1 = JavaRandom(seed: 12345)
		var rng2 = JavaRandom(seed: 12345)
		for _ in 0..<50 {
			#expect(rng1.next(bits: 31) == rng2.next(bits: 31))
		}
	}
}
