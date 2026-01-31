//
//  FountainCodec.swift
//  Meshtastic
//
//  Fountain code (LT codes) implementation for reliable transfer over lossy mesh networks
//  Based on the ATAK Meshtastic plugin protocol
//

import Foundation
import CryptoKit
import OSLog

// MARK: - Constants

enum FountainConstants {
	/// Magic bytes identifying fountain packets: "FTN"
	static let magic: [UInt8] = [0x46, 0x54, 0x4E]

	/// Maximum payload size per block
	static let blockSize = 220

	/// Header size for data blocks
	static let dataHeaderSize = 11

	/// Size threshold for fountain coding (below this, send directly)
	static let fountainThreshold = 233

	/// Transfer type: CoT event
	static let transferTypeCot: UInt8 = 0x00

	/// Transfer type: File transfer
	static let transferTypeFile: UInt8 = 0x01

	/// ACK type: Transfer complete
	static let ackTypeComplete: UInt8 = 0x02

	/// ACK type: Need more blocks
	static let ackTypeNeedMore: UInt8 = 0x03

	/// ACK packet size
	static let ackPacketSize = 19
}

// MARK: - Fountain Packet Types

/// A received fountain block with its metadata
struct FountainBlock {
	let seed: UInt16
	var indices: Set<Int>
	var payload: Data

	func copy() -> FountainBlock {
		return FountainBlock(seed: seed, indices: indices, payload: payload)
	}
}

/// State for receiving a fountain-coded transfer
class FountainReceiveState {
	let transferId: UInt32
	// swiftlint:disable:next identifier_name
	let K: Int
	let totalLength: Int
	var blocks: [FountainBlock] = []
	let createdAt: Date

	// swiftlint:disable:next identifier_name
	init(transferId: UInt32, K: Int, totalLength: Int) {
		self.transferId = transferId
		self.K = K
		self.totalLength = totalLength
		self.createdAt = Date()
	}

	func addBlock(_ block: FountainBlock) {
		// Don't add duplicate seeds
		if !blocks.contains(where: { $0.seed == block.seed }) {
			blocks.append(block)
		}
	}

	var isExpired: Bool {
		// Expire after 60 seconds
		return Date().timeIntervalSince(createdAt) > 60
	}
}

/// Parsed fountain data block header
struct FountainDataHeader {
	let transferId: UInt32  // 24-bit, stored in lower 24 bits
	let seed: UInt16
	// swiftlint:disable:next identifier_name
	let K: UInt8
	let totalLength: UInt16
}

/// Parsed fountain ACK packet
struct FountainAck {
	let transferId: UInt32
	let type: UInt8
	let received: UInt16
	let needed: UInt16
	let dataHash: Data
}

// MARK: - Java-Compatible Random Number Generator

/// Java's java.util.Random implementation (Linear Congruential Generator)
/// CRITICAL: Must match Java exactly for Android interoperability
struct JavaRandom {
	private var seed: Int64

	init(seed: Int64) {
		// Java's Random constructor: (seed ^ 0x5DEECE66DL) & ((1L << 48) - 1)
		self.seed = (seed ^ 0x5DEECE66D) & ((Int64(1) << 48) - 1)
	}

	/// Generate next random bits (Java's protected next(int bits) method)
	mutating func next(bits: Int) -> Int32 {
		// seed = (seed * 0x5DEECE66DL + 0xBL) & ((1L << 48) - 1)
		seed = (seed &* 0x5DEECE66D &+ 0xB) & ((Int64(1) << 48) - 1)
		return Int32(truncatingIfNeeded: seed >> (48 - bits))
	}

	/// Generate random int in [0, bound) - matches Java's nextInt(int bound)
	mutating func nextInt(bound: Int) -> Int {
		guard bound > 0 else { return 0 }

		// Power of 2 optimization
		if (bound & -bound) == bound {
			return Int((Int64(bound) &* Int64(next(bits: 31))) >> 31)
		}

		// Rejection sampling to avoid modulo bias
		var bits: Int32
		var val: Int
		repeat {
			bits = next(bits: 31)
			val = Int(bits) % bound
		} while bits - Int32(val) + Int32(bound - 1) < 0

		return val
	}

	/// Generate random double in [0.0, 1.0) - matches Java's nextDouble()
	mutating func nextDouble() -> Double {
		let high = Int64(next(bits: 26))
		let low = Int64(next(bits: 27))
		return Double((high << 27) + low) / Double(Int64(1) << 53)
	}
}

// MARK: - Fountain Codec

/// Encoder and decoder for fountain-coded transfers
final class FountainCodec {

	static let shared = FountainCodec()

	private var receiveStates: [UInt32: FountainReceiveState] = [:]

	private init() {}

	// MARK: - Transfer ID Generation

	/// Generate a unique random 24-bit transfer ID
	/// CRITICAL: Must be random to avoid collisions with recent transfers
	func generateTransferId() -> UInt32 {
		let random = UInt32.random(in: 0...0xFFFFFF)
		let time = UInt32(Date().timeIntervalSince1970) & 0xFFFF
		return (random ^ time) & 0xFFFFFF
	}

	// MARK: - Encoding

	/// Encode data into fountain-coded blocks
	/// - Parameters:
	///   - data: The data to encode (should include transfer type prefix)
	///   - transferId: Unique transfer ID for this transmission
	/// - Returns: Array of encoded block packets ready for transmission
	func encode(data: Data, transferId: UInt32) -> [Data] {
		// Guard against empty data
		guard !data.isEmpty else {
			Logger.tak.warning("Fountain encode: empty data")
			return []
		}
		// swiftlint:disable:next identifier_name
		let K = max(1, Int(ceil(Double(data.count) / Double(FountainConstants.blockSize))))
		let overhead = getAdaptiveOverhead(K)
		let blocksToSend = max(1, Int(ceil(Double(K) * (1.0 + overhead))))

		// Split into source blocks (pad last block with zeros)
		let sourceBlocks = splitIntoBlocks(data: data, K: K)

		// Debug: Log source block hashes to verify they're different
		for (i, block) in sourceBlocks.enumerated() {
			let hash = block.prefix(8).map { String(format: "%02X", $0) }.joined()
			Logger.tak.debug("Fountain sourceBlock[\(i)]: first 8 bytes = \(hash)")
		}

		var packets: [Data] = []

		for i in 0..<blocksToSend {
			let seed = generateSeed(transferId: transferId, blockIndex: i)

			// Generate indices - must match Android's algorithm exactly
			let indices = generateBlockIndices(seed: seed, K: K, blockIndex: i)

			Logger.tak.debug("Fountain block \(i): seed=\(seed), degree=\(indices.count), indices=\(indices.sorted())")

			// XOR selected source blocks together
			var blockPayload = Data(repeating: 0, count: FountainConstants.blockSize)
			for idx in indices {
				let before = blockPayload.prefix(4).map { String(format: "%02X", $0) }.joined()
				blockPayload = xor(blockPayload, sourceBlocks[idx])
				let after = blockPayload.prefix(4).map { String(format: "%02X", $0) }.joined()
				Logger.tak.debug("  XOR with sourceBlock[\(idx)]: \(before) → \(after)")
			}

			// Log final payload hash
			let payloadHash = blockPayload.prefix(8).map { String(format: "%02X", $0) }.joined()
			Logger.tak.debug("  Final payload first 8 bytes: \(payloadHash)")

			// Build data block packet
			let packet = buildDataBlock(
				transferId: transferId,
				seed: seed,
				K: UInt8(K),
				totalLength: UInt16(data.count),
				payload: blockPayload
			)
			packets.append(packet)
		}

		Logger.tak.info("Fountain encode: \(data.count) bytes → \(K) source blocks → \(blocksToSend) packets")
		return packets
	}

	/// Split data into K blocks, padding the last block with zeros
	// swiftlint:disable:next identifier_name
	private func splitIntoBlocks(data: Data, K: Int) -> [Data] {
		var blocks: [Data] = []
		for i in 0..<K {
			let start = i * FountainConstants.blockSize
			let end = min(start + FountainConstants.blockSize, data.count)

			var block: Data
			if start < data.count {
				// IMPORTANT: Use Data() to rebase indices to 0
				// Data slices keep original indices which causes crashes
				block = Data(data[start..<end])
				// Pad if necessary
				if block.count < FountainConstants.blockSize {
					block.append(Data(repeating: 0, count: FountainConstants.blockSize - block.count))
				}
			} else {
				block = Data(repeating: 0, count: FountainConstants.blockSize)
			}
			blocks.append(block)
		}
		return blocks
	}

	/// Build a fountain data block packet
	// swiftlint:disable:next identifier_name
	private func buildDataBlock(transferId: UInt32, seed: UInt16, K: UInt8, totalLength: UInt16, payload: Data) -> Data {
		var packet = Data()

		// Magic bytes
		packet.append(contentsOf: FountainConstants.magic)

		// Transfer ID (24-bit, big-endian)
		packet.append(UInt8((transferId >> 16) & 0xFF))
		packet.append(UInt8((transferId >> 8) & 0xFF))
		packet.append(UInt8(transferId & 0xFF))

		// Seed (16-bit, big-endian)
		packet.append(UInt8((seed >> 8) & 0xFF))
		packet.append(UInt8(seed & 0xFF))

		// K (number of source blocks)
		packet.append(K)

		// Total length (16-bit, big-endian)
		packet.append(UInt8((totalLength >> 8) & 0xFF))
		packet.append(UInt8(totalLength & 0xFF))

		// Payload
		packet.append(payload)

		return packet
	}

	// MARK: - Decoding

	/// Check if data is a fountain packet
	static func isFountainPacket(_ data: Data) -> Bool {
		guard data.count >= 3 else { return false }
		return data[0] == FountainConstants.magic[0]
			&& data[1] == FountainConstants.magic[1]
			&& data[2] == FountainConstants.magic[2]
	}

	/// Parse a fountain data block header
	func parseDataHeader(_ data: Data) -> FountainDataHeader? {
		guard data.count >= FountainConstants.dataHeaderSize else { return nil }
		guard Self.isFountainPacket(data) else { return nil }

		let transferId = (UInt32(data[3]) << 16) | (UInt32(data[4]) << 8) | UInt32(data[5])
		let seed = (UInt16(data[6]) << 8) | UInt16(data[7])
		// swiftlint:disable:next identifier_name
		let K = data[8]
		let totalLength = (UInt16(data[9]) << 8) | UInt16(data[10])

		return FountainDataHeader(transferId: transferId, seed: seed, K: K, totalLength: totalLength)
	}

	/// Handle an incoming fountain packet
	/// - Parameters:
	///   - data: The raw packet data
	///   - senderNodeId: ID of the sending node
	/// - Returns: Decoded data if transfer is complete, nil otherwise
	func handleIncomingPacket(_ data: Data, senderNodeId: UInt32) -> (data: Data, transferId: UInt32)? {
		// Clean up expired states
		cleanupExpiredStates()

		guard let header = parseDataHeader(data) else {
			Logger.tak.warning("Invalid fountain packet header")
			return nil
		}

		let payload = data.dropFirst(FountainConstants.dataHeaderSize)
		guard payload.count == FountainConstants.blockSize else {
			Logger.tak.warning("Invalid fountain payload size: \(payload.count)")
			return nil
		}

		// Get or create receive state
		let state: FountainReceiveState
		if let existing = receiveStates[header.transferId] {
			state = existing
		} else {
			state = FountainReceiveState(
				transferId: header.transferId,
				K: Int(header.K),
				totalLength: Int(header.totalLength)
			)
			receiveStates[header.transferId] = state
			Logger.tak.debug("New fountain transfer: id=\(header.transferId), K=\(header.K), len=\(header.totalLength)")
		}

		// Regenerate source indices from seed
		let indices = regenerateIndices(seed: header.seed, K: state.K, transferId: header.transferId)

		// Add block
		let block = FountainBlock(seed: header.seed, indices: indices, payload: Data(payload))
		state.addBlock(block)

		Logger.tak.debug("Fountain block received: xferId=\(header.transferId), seed=\(header.seed), blocks=\(state.blocks.count)/\(state.K)")

		// Try to decode if we have enough blocks
		if state.blocks.count >= state.K {
			if let decoded = peelingDecode(state) {
				// Remove completed state
				receiveStates.removeValue(forKey: header.transferId)
				Logger.tak.info("Fountain decode complete: \(decoded.count) bytes from \(state.blocks.count) blocks")
				return (decoded, header.transferId)
			}
		}

		return nil
	}

	/// Build an ACK packet
	func buildAck(transferId: UInt32, type: UInt8, received: UInt16, needed: UInt16, dataHash: Data) -> Data {
		var packet = Data()

		// Magic bytes
		packet.append(contentsOf: FountainConstants.magic)

		// Transfer ID (24-bit, big-endian)
		packet.append(UInt8((transferId >> 16) & 0xFF))
		packet.append(UInt8((transferId >> 8) & 0xFF))
		packet.append(UInt8(transferId & 0xFF))

		// Type
		packet.append(type)

		// Received (16-bit, big-endian)
		packet.append(UInt8((received >> 8) & 0xFF))
		packet.append(UInt8(received & 0xFF))

		// Needed (16-bit, big-endian)
		packet.append(UInt8((needed >> 8) & 0xFF))
		packet.append(UInt8(needed & 0xFF))

		// Data hash (8 bytes)
		packet.append(dataHash.prefix(8))

		return packet
	}

	/// Parse an ACK packet
	func parseAck(_ data: Data) -> FountainAck? {
		guard data.count >= FountainConstants.ackPacketSize else { return nil }
		guard Self.isFountainPacket(data) else { return nil }

		let transferId = (UInt32(data[3]) << 16) | (UInt32(data[4]) << 8) | UInt32(data[5])
		let type = data[6]
		let received = (UInt16(data[7]) << 8) | UInt16(data[8])
		let needed = (UInt16(data[9]) << 8) | UInt16(data[10])
		let dataHash = Data(data[11..<19])

		return FountainAck(transferId: transferId, type: type, received: received, needed: needed, dataHash: dataHash)
	}

	// MARK: - Peeling Decoder

	/// Decode using the peeling algorithm
	private func peelingDecode(_ state: FountainReceiveState) -> Data? {
		var decoded: [Int: Data] = [:]
		var workingBlocks = state.blocks.map { $0.copy() }

		var progress = true
		while progress && decoded.count < state.K {
			progress = false

			for i in 0..<workingBlocks.count {
				var block = workingBlocks[i]

				// Remove already-decoded indices by XORing out their data
				for idx in block.indices {
					if let decodedBlock = decoded[idx] {
						block.payload = xor(block.payload, decodedBlock)
						block.indices.remove(idx)
					}
				}
				workingBlocks[i] = block

				// If only one unknown remains, we can decode it
				if block.indices.count == 1 {
					let idx = block.indices.first!
					decoded[idx] = block.payload
					progress = true
				}
			}
		}

		// Check if complete
		guard decoded.count >= state.K else {
			Logger.tak.debug("Peeling decode incomplete: \(decoded.count)/\(state.K) blocks decoded")
			return nil
		}

		// Reassemble original data
		var result = Data()
		for i in 0..<state.K {
			if let block = decoded[i] {
				result.append(block)
			} else {
				Logger.tak.warning("Missing block \(i) in decoded data")
				return nil
			}
		}

		// Trim to original length
		return Data(result.prefix(state.totalLength))
	}

	// MARK: - Helper Functions

	/// Get adaptive overhead based on K
	// swiftlint:disable:next identifier_name
	private func getAdaptiveOverhead(_ K: Int) -> Double {
		if K <= 10 { return 0.50 }      // 50% for very small
		else if K <= 50 { return 0.25 } // 25% for small
		else { return 0.15 }            // 15% for larger
	}

	/// Generate deterministic seed from transfer ID and block index
	private func generateSeed(transferId: UInt32, blockIndex: Int) -> UInt16 {
		let combined = Int(transferId) * 31337 + blockIndex * 7919
		return UInt16(combined & 0xFFFF)
	}

	/// Generate indices for encoding a block
	/// CRITICAL: Must match Android's exact algorithm for interoperability
	/// Android uses Java's java.util.Random (LCG) with specific block 0 handling
	// swiftlint:disable:next identifier_name
	private func generateBlockIndices(seed: UInt16, K: Int, blockIndex: Int) -> Set<Int> {
		var rng = JavaRandom(seed: Int64(seed))

		// ALWAYS sample degree first (advances RNG state) - matches Android
		let sampledDegree = sampleRobustSolitonDegree(&rng, K: K)

		// For block 0: ignore sampled degree, use degree=1 instead
		// For other blocks: use the sampled degree
		// This matches Android's isFirstBlock logic
		let degree = (blockIndex == 0) ? 1 : sampledDegree

		// Select indices with RNG now advanced past degree sampling
		return selectIndices(&rng, K: K, degree: degree)
	}

	/// Regenerate source indices from seed (must match sender's algorithm)
	/// CRITICAL: Must use same RNG flow as generateBlockIndices for Android interop
	// swiftlint:disable:next identifier_name
	private func regenerateIndices(seed: UInt16, K: Int, transferId: UInt32) -> Set<Int> {
		var rng = JavaRandom(seed: Int64(seed))

		// ALWAYS sample degree first (advances RNG state) - matches Android
		let sampledDegree = sampleRobustSolitonDegree(&rng, K: K)

		// Check if this is block 0 (forced degree=1)
		let expectedSeed0 = generateSeed(transferId: transferId, blockIndex: 0)
		let degree = (seed == expectedSeed0) ? 1 : sampledDegree

		// Select indices with RNG now advanced past degree sampling
		return selectIndices(&rng, K: K, degree: degree)
	}

	/// Select source block indices using provided RNG
	/// Matches Android's selectIndices algorithm exactly
	// swiftlint:disable:next identifier_name
	private func selectIndices(_ rng: inout JavaRandom, K: Int, degree: Int) -> Set<Int> {
		var indices = Set<Int>()

		// Select 'degree' unique indices
		while indices.count < degree && indices.count < K {
			let idx = rng.nextInt(bound: K)
			indices.insert(idx)
		}

		return indices
	}

	/// Sample degree from Robust Soliton distribution using provided RNG
	/// Matches Android's sampleDegree algorithm exactly
	// swiftlint:disable:next identifier_name
	// swiftlint:disable:next identifier_name
	private func sampleRobustSolitonDegree(_ rng: inout JavaRandom, K: Int) -> Int {
		let cdf = buildRobustSolitonCDF(K: K)
		let u = rng.nextDouble()

		for d in 1...K {
			if u <= cdf[d] {
				return d
			}
		}
		return K
	}

	/// Build CDF for Robust Soliton distribution
	// swiftlint:disable:next identifier_name
	private func buildRobustSolitonCDF(K: Int, c: Double = 0.1, delta: Double = 0.5) -> [Double] {
		// Guard against K <= 0
		guard K > 0 else {
			return [1.0]  // Single element CDF
		}

		// Ideal Soliton distribution
		var rho = [Double](repeating: 0, count: K + 1)
		rho[1] = 1.0 / Double(K)
		for d in 2...K {
			rho[d] = 1.0 / (Double(d) * Double(d - 1))
		}

		// Robust Soliton addition (tau)
		// swiftlint:disable:next identifier_name
		let R = c * log(Double(K) / delta) * sqrt(Double(K))
		var tau = [Double](repeating: 0, count: K + 1)
		let threshold = Int(Double(K) / R)

		for d in 1...K {
			if d < threshold {
				tau[d] = R / (Double(d) * Double(K))
			} else if d == threshold {
				tau[d] = R * log(R / delta) / Double(K)
			}
		}

		// Combine and normalize
		var mu = [Double](repeating: 0, count: K + 1)
		var sum = 0.0
		for d in 1...K {
			mu[d] = rho[d] + tau[d]
			sum += mu[d]
		}

		// Build CDF
		var cdf = [Double](repeating: 0, count: K + 1)
		var cumulative = 0.0
		for d in 1...K {
			cumulative += mu[d] / sum
			cdf[d] = cumulative
		}

		return cdf
	}

	/// XOR two data blocks
	private func xor(_ a: Data, _ b: Data) -> Data {
		// IMPORTANT: Rebase inputs to ensure 0-based indices
		// Data slices keep original indices which causes crashes when accessing [i]
		let aData = a.startIndex == 0 ? a : Data(a)
		let bData = b.startIndex == 0 ? b : Data(b)

		var result = Data(count: max(aData.count, bData.count))
		for i in 0..<result.count {
			let byteA = i < aData.count ? aData[i] : 0
			let byteB = i < bData.count ? bData[i] : 0
			result[i] = byteA ^ byteB
		}
		return result
	}

	/// Compute SHA-256 hash (first 8 bytes for ACK)
	static func computeHash(_ data: Data) -> Data {
		let digest = SHA256.hash(data: data)
		return Data(digest.prefix(8))
	}

	/// Clean up expired receive states
	private func cleanupExpiredStates() {
		let expiredIds = receiveStates.filter { $0.value.isExpired }.map { $0.key }
		for id in expiredIds {
			receiveStates.removeValue(forKey: id)
			Logger.tak.debug("Cleaned up expired fountain state: \(id)")
		}
	}
}
