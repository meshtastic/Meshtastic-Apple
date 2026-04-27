// FountainCodecDetailedTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

// MARK: - JavaRandom Deterministic Tests

@Suite("JavaRandom Deterministic Output")
struct JavaRandomDeterministicTests {

	@Test func sameSeed_sameOutput() {
		var rng1 = JavaRandom(seed: 42)
		var rng2 = JavaRandom(seed: 42)
		for _ in 0..<10 {
			#expect(rng1.next(bits: 32) == rng2.next(bits: 32))
		}
	}

	@Test func differentSeeds_differentOutput() {
		var rng1 = JavaRandom(seed: 42)
		var rng2 = JavaRandom(seed: 99)
		let v1 = rng1.next(bits: 32)
		let v2 = rng2.next(bits: 32)
		#expect(v1 != v2)
	}

	@Test func nextInt_inBounds() {
		var rng = JavaRandom(seed: 12345)
		for _ in 0..<100 {
			let val = rng.nextInt(bound: 10)
			#expect(val >= 0 && val < 10)
		}
	}

	@Test func nextInt_boundZero_returnsZero() {
		var rng = JavaRandom(seed: 1)
		let val = rng.nextInt(bound: 0)
		#expect(val == 0)
	}

	@Test func nextInt_powerOfTwo() {
		var rng = JavaRandom(seed: 555)
		for _ in 0..<50 {
			let val = rng.nextInt(bound: 8)
			#expect(val >= 0 && val < 8)
		}
	}

	@Test func nextDouble_inRange() {
		var rng = JavaRandom(seed: 42)
		for _ in 0..<100 {
			let val = rng.nextDouble()
			#expect(val >= 0.0 && val < 1.0)
		}
	}

	@Test func next_variousBitWidths() {
		var rng = JavaRandom(seed: 7)
		// 1-bit
		let bit1 = rng.next(bits: 1)
		#expect(bit1 == 0 || bit1 == -1 || bit1 == 1) // sign-extended from MSB
		// 16-bit
		let bit16 = rng.next(bits: 16)
		#expect(bit16 >= Int32(Int16.min) && bit16 <= Int32(Int16.max))
		// 31-bit
		let bit31 = rng.next(bits: 31)
		#expect(bit31 >= 0)
	}
}

// MARK: - FountainConstants Tests

@Suite("FountainConstants Values Detailed")
struct FountainConstantsDetailedTests {

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

	@Test func transferTypes() {
		#expect(FountainConstants.transferTypeCot == 0x00)
		#expect(FountainConstants.transferTypeFile == 0x01)
	}

	@Test func ackTypes() {
		#expect(FountainConstants.ackTypeComplete == 0x02)
		#expect(FountainConstants.ackTypeNeedMore == 0x03)
	}

	@Test func ackPacketSize_is19() {
		#expect(FountainConstants.ackPacketSize == 19)
	}
}

// MARK: - FountainCodec Encode/Decode Tests

@Suite("FountainCodec Encode Decode")
struct FountainCodecEncodeDecodeTests {

	@Test func encode_emptyData_returnsEmpty() {
		let result = FountainCodec.shared.encode(data: Data(), transferId: 1)
		#expect(result.isEmpty)
	}

	@Test func encode_smallData_producesPackets() {
		let data = Data(repeating: 0xAB, count: 100)
		let packets = FountainCodec.shared.encode(data: data, transferId: 12345)
		#expect(!packets.isEmpty)
		// Each packet should start with FTN magic
		for packet in packets {
			#expect(packet.count >= FountainConstants.dataHeaderSize)
			#expect(packet[0] == 0x46) // F
			#expect(packet[1] == 0x54) // T
			#expect(packet[2] == 0x4E) // N
		}
	}

	@Test func encode_largeData_producesMorePackets() {
		let smallData = Data(repeating: 0xAB, count: 100)
		let largeData = Data(repeating: 0xCD, count: 1000)
		let smallPackets = FountainCodec.shared.encode(data: smallData, transferId: 1)
		let largePackets = FountainCodec.shared.encode(data: largeData, transferId: 2)
		#expect(largePackets.count > smallPackets.count)
	}

	@Test func isFountainPacket_validMagic() {
		var data = Data([0x46, 0x54, 0x4E, 0x00, 0x00])
		#expect(FountainCodec.isFountainPacket(data))
	}

	@Test func isFountainPacket_invalidMagic() {
		let data = Data([0x00, 0x01, 0x02])
		#expect(!FountainCodec.isFountainPacket(data))
	}

	@Test func isFountainPacket_tooShort() {
		let data = Data([0x46, 0x54])
		#expect(!FountainCodec.isFountainPacket(data))
	}

	@Test func parseDataHeader_valid() {
		// Build a valid header: FTN + transferId(3) + seed(2) + K(1) + totalLength(2) + payload
		var packet = Data()
		packet.append(contentsOf: [0x46, 0x54, 0x4E]) // magic
		packet.append(contentsOf: [0x00, 0x01, 0x23]) // transferId = 0x000123
		packet.append(contentsOf: [0x00, 0x42]) // seed = 66
		packet.append(0x03) // K = 3
		packet.append(contentsOf: [0x01, 0xF4]) // totalLength = 500
		// Need at least dataHeaderSize bytes
		let header = FountainCodec.shared.parseDataHeader(packet)
		#expect(header != nil)
		#expect(header!.transferId == 0x000123)
		#expect(header!.seed == 66)
		#expect(header!.K == 3)
		#expect(header!.totalLength == 500)
	}

	@Test func parseDataHeader_tooShort() {
		let packet = Data([0x46, 0x54, 0x4E, 0x00, 0x01])
		let header = FountainCodec.shared.parseDataHeader(packet)
		#expect(header == nil)
	}

	@Test func parseDataHeader_wrongMagic() {
		let packet = Data(repeating: 0x00, count: 20)
		let header = FountainCodec.shared.parseDataHeader(packet)
		#expect(header == nil)
	}
}

// MARK: - FountainCodec ACK Tests

@Suite("FountainCodec ACK")
struct FountainCodecACKTests {

	@Test func buildAck_correctSize() {
		let hash = Data(repeating: 0xAA, count: 8)
		let ack = FountainCodec.shared.buildAck(
			transferId: 0x123456,
			type: FountainConstants.ackTypeComplete,
			received: 5,
			needed: 0,
			dataHash: hash
		)
		#expect(ack.count == FountainConstants.ackPacketSize)
	}

	@Test func buildAck_hasMagic() {
		let hash = Data(repeating: 0xBB, count: 8)
		let ack = FountainCodec.shared.buildAck(
			transferId: 1,
			type: FountainConstants.ackTypeNeedMore,
			received: 2,
			needed: 3,
			dataHash: hash
		)
		#expect(ack[0] == 0x46)
		#expect(ack[1] == 0x54)
		#expect(ack[2] == 0x4E)
	}

	@Test func buildAck_parseAck_roundTrip() {
		let hash = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
		let transferId: UInt32 = 0xABCDEF & 0xFFFFFF
		let ack = FountainCodec.shared.buildAck(
			transferId: transferId,
			type: FountainConstants.ackTypeComplete,
			received: 10,
			needed: 0,
			dataHash: hash
		)
		let parsed = FountainCodec.shared.parseAck(ack)
		#expect(parsed != nil)
		#expect(parsed!.transferId == (transferId & 0xFFFFFF))
		#expect(parsed!.type == FountainConstants.ackTypeComplete)
		#expect(parsed!.received == 10)
		#expect(parsed!.needed == 0)
		#expect(parsed!.dataHash == hash)
	}

	@Test func parseAck_tooShort() {
		let data = Data(repeating: 0x46, count: 10)
		let parsed = FountainCodec.shared.parseAck(data)
		#expect(parsed == nil)
	}

	@Test func parseAck_wrongMagic() {
		let data = Data(repeating: 0x00, count: FountainConstants.ackPacketSize)
		let parsed = FountainCodec.shared.parseAck(data)
		#expect(parsed == nil)
	}
}

// MARK: - FountainCodec computeHash Tests

@Suite("FountainCodec Hash")
struct FountainCodecHashTests {

	@Test func computeHash_deterministic() {
		let data = Data("Hello, World!".utf8)
		let hash1 = FountainCodec.computeHash(data)
		let hash2 = FountainCodec.computeHash(data)
		#expect(hash1 == hash2)
	}

	@Test func computeHash_differentData_differentHash() {
		let hash1 = FountainCodec.computeHash(Data("abc".utf8))
		let hash2 = FountainCodec.computeHash(Data("xyz".utf8))
		#expect(hash1 != hash2)
	}

	@Test func computeHash_size() {
		let hash = FountainCodec.computeHash(Data("test".utf8))
		// SHA256 truncated to 8 bytes
		#expect(hash.count == 8)
	}
}

// MARK: - FountainCodec generateTransferId Tests

@Suite("FountainCodec TransferId")
struct FountainCodecTransferIdTests {

	@Test func generateTransferId_is24Bit() {
		for _ in 0..<20 {
			let id = FountainCodec.shared.generateTransferId()
			#expect(id <= 0xFFFFFF)
		}
	}

	@Test func generateTransferId_varies() {
		var ids = Set<UInt32>()
		for _ in 0..<10 {
			ids.insert(FountainCodec.shared.generateTransferId())
		}
		// Should get at least a few unique IDs
		#expect(ids.count > 1)
	}
}

// MARK: - FountainBlock Tests

@Suite("FountainBlock Struct")
struct FountainBlockStructTests {

	@Test func copy_createsSeparateInstance() {
		let block = FountainBlock(
			seed: 42,
			indices: [0, 1, 2],
			payload: Data(repeating: 0xAA, count: 10)
		)
		var copied = block.copy()
		copied.indices.insert(99)
		#expect(!block.indices.contains(99))
		#expect(copied.indices.contains(99))
	}
}

// MARK: - FountainReceiveState Tests

@Suite("FountainReceiveState Detailed")
struct FountainReceiveStateDetailedTests {

	@Test func init_setsProperties() {
		let state = FountainReceiveState(transferId: 123, K: 5, totalLength: 1000)
		#expect(state.transferId == 123)
		#expect(state.K == 5)
		#expect(state.totalLength == 1000)
		#expect(state.blocks.isEmpty)
	}

	@Test func addBlock_addsDifferentSeeds() {
		let state = FountainReceiveState(transferId: 1, K: 2, totalLength: 100)
		let block1 = FountainBlock(seed: 1, indices: [0], payload: Data(repeating: 0, count: 10))
		let block2 = FountainBlock(seed: 2, indices: [1], payload: Data(repeating: 1, count: 10))
		state.addBlock(block1)
		state.addBlock(block2)
		#expect(state.blocks.count == 2)
	}

	@Test func addBlock_ignoresDuplicateSeed() {
		let state = FountainReceiveState(transferId: 1, K: 2, totalLength: 100)
		let block1 = FountainBlock(seed: 1, indices: [0], payload: Data(repeating: 0, count: 10))
		let block2 = FountainBlock(seed: 1, indices: [0], payload: Data(repeating: 1, count: 10))
		state.addBlock(block1)
		state.addBlock(block2)
		#expect(state.blocks.count == 1)
	}

	@Test func isExpired_newState_notExpired() {
		let state = FountainReceiveState(transferId: 1, K: 1, totalLength: 10)
		#expect(!state.isExpired)
	}
}

// MARK: - FountainCodec Encode then Decode RoundTrip

@Suite("FountainCodec Full RoundTrip")
struct FountainCodecFullRoundTripTests {

	@Test func encode_decode_singleBlock() {
		// Data small enough for 1 source block (< 220 bytes)
		let original = Data("Hello, this is a test payload for fountain coding!".utf8)
		let transferId: UInt32 = 0x001234
		let packets = FountainCodec.shared.encode(data: original, transferId: transferId)
		#expect(!packets.isEmpty)

		// Feed packets into decoder
		var decoded: (data: Data, transferId: UInt32)?
		for packet in packets {
			if let result = FountainCodec.shared.handleIncomingPacket(packet, senderNodeId: 999) {
				decoded = result
				break
			}
		}

		#expect(decoded != nil)
		if let decoded {
			#expect(decoded.data == original)
			#expect(decoded.transferId == transferId)
		}
	}

	@Test func encode_decode_multiBlock() {
		// Data requiring multiple source blocks (> 220 bytes)
		var original = Data()
		for i in 0..<500 {
			original.append(UInt8(i % 256))
		}
		let transferId: UInt32 = 0x005678
		let packets = FountainCodec.shared.encode(data: original, transferId: transferId)
		#expect(packets.count > 1)

		// Feed all packets
		var decoded: (data: Data, transferId: UInt32)?
		for packet in packets {
			if let result = FountainCodec.shared.handleIncomingPacket(packet, senderNodeId: 888) {
				decoded = result
				break
			}
		}

		#expect(decoded != nil)
		if let decoded {
			#expect(decoded.data == original)
		}
	}
}

// MARK: - UserDefaults.Keys Tests

@Suite("UserDefaults Keys")
struct UserDefaultsKeysEnumTests {

	@Test func allCases_haveRawValues() {
		for key in UserDefaults.Keys.allCases {
			#expect(!key.rawValue.isEmpty)
		}
	}

	@Test func specificKeys() {
		#expect(UserDefaults.Keys.preferredPeripheralId.rawValue == "preferredPeripheralId")
		#expect(UserDefaults.Keys.provideLocation.rawValue == "provideLocation")
		#expect(UserDefaults.Keys.mapLayer.rawValue == "mapLayer")
	}
}
