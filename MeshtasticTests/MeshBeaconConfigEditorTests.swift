// MARK: MeshBeaconConfigEditorTests
//
//  Locks down the blocking client-side validation and flag-bitfield handling for the
//  Mesh Beacon module config editor (contract C2, FR-010/FR-011/FR-013, research D4):
//   - the beacon message is capped at 100 UTF-8 bytes (100 ok, 101 blocks save);
//   - the broadcast interval must be ≥ 3600 s (3600 ok, 3599 blocks save);
//   - toggling FLAG_LISTEN_ENABLED / FLAG_BROADCAST_ENABLED preserves every other bit,
//     including the firmware-managed FLAG_LEGACY_SPLIT.
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("MeshBeaconConfigEditor")
struct MeshBeaconConfigEditorTests {

	// MARK: - Message length (FR-011)

	@Test func message100BytesIsValid() {
		let message = String(repeating: "a", count: 100)
		#expect(MeshBeaconValidation.messageByteCount(message) == 100)
		#expect(MeshBeaconValidation.isMessageValid(message))
	}

	@Test func message101BytesBlocksSave() {
		let message = String(repeating: "a", count: 101)
		#expect(MeshBeaconValidation.messageByteCount(message) == 101)
		#expect(!MeshBeaconValidation.isMessageValid(message))
	}

	@Test func messageByteCountUsesUTF8NotCharacters() {
		// A 4-byte emoji: 25 of them = 100 bytes (valid), 26 = 104 bytes (blocks).
		let ok = String(repeating: "😀", count: 25)
		let tooBig = String(repeating: "😀", count: 26)
		#expect(MeshBeaconValidation.messageByteCount(ok) == 100)
		#expect(MeshBeaconValidation.isMessageValid(ok))
		#expect(!MeshBeaconValidation.isMessageValid(tooBig))
	}

	@Test func emptyMessageIsValid() {
		#expect(MeshBeaconValidation.isMessageValid(""))
	}

	// MARK: - Interval (FR-013)

	@Test func interval3600IsValid() {
		#expect(MeshBeaconValidation.isIntervalValid(3600))
	}

	@Test func interval3599BlocksSave() {
		#expect(!MeshBeaconValidation.isIntervalValid(3599))
	}

	@Test func intervalAboveMinimumIsValid() {
		#expect(MeshBeaconValidation.isIntervalValid(7200))
	}

	@Test func intervalZeroBlocksSave() {
		#expect(!MeshBeaconValidation.isIntervalValid(0))
	}

	// MARK: - Flag bitfield preserves other bits (FR-010 / D4)

	@Test func settingListenPreservesLegacySplit() {
		// Start with only FLAG_LEGACY_SPLIT (4) set.
		let start = MeshBeaconFlags.legacySplit
		let result = MeshBeaconFlags.setting(start, MeshBeaconFlags.listenEnabled, to: true)
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.listenEnabled))
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.legacySplit))
		#expect(result == 5) // 4 | 1
	}

	@Test func clearingListenPreservesLegacySplit() {
		// Start with listen + legacy-split set (1 | 4 = 5).
		let start = MeshBeaconFlags.listenEnabled | MeshBeaconFlags.legacySplit
		let result = MeshBeaconFlags.setting(start, MeshBeaconFlags.listenEnabled, to: false)
		#expect(!MeshBeaconFlags.has(result, MeshBeaconFlags.listenEnabled))
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.legacySplit))
		#expect(result == MeshBeaconFlags.legacySplit)
	}

	@Test func togglingBroadcastPreservesListenAndLegacySplit() {
		// listen + legacy-split set, broadcast off; enable broadcast.
		let start = MeshBeaconFlags.listenEnabled | MeshBeaconFlags.legacySplit
		let result = MeshBeaconFlags.setting(start, MeshBeaconFlags.broadcastEnabled, to: true)
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.broadcastEnabled))
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.listenEnabled))
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.legacySplit))
		#expect(result == 7) // 1 | 2 | 4
	}

	@Test func settingAFlagAlreadySetIsIdempotent() {
		let start = MeshBeaconFlags.listenEnabled | MeshBeaconFlags.legacySplit
		let result = MeshBeaconFlags.setting(start, MeshBeaconFlags.listenEnabled, to: true)
		#expect(result == start)
	}

	@Test func hasReturnsFalseForUnsetFlag() {
		#expect(!MeshBeaconFlags.has(MeshBeaconFlags.broadcastEnabled, MeshBeaconFlags.listenEnabled))
	}
}
