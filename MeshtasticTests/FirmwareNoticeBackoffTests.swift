//
//  FirmwareNoticeBackoffTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/18/26.
//

import Testing
import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("Firmware notice backoff")
@MainActor
struct FirmwareNoticeBackoffTests {

	private func notice(_ message: String, level: LogRecord.Level = .warning) -> ClientNotification {
		var notification = ClientNotification()
		notification.message = message
		notification.level = level
		return notification
	}

	/// The ladder: immediate, then 5 min, 30 min, 2 h, then every 12 h.
	@Test func repeatsBackOffOnTheLadder() {
		let manager = AccessoryManager()
		let key = "position-off"
		let start = Date(timeIntervalSince1970: 1_000_000)

		// First occurrence alerts immediately.
		#expect(manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start))
		// A second one moments later does not.
		#expect(!manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start + 60))
		// Past five minutes it does.
		#expect(manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start + 301))
		// Now the wait is thirty minutes.
		#expect(!manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start + 1_200))
		#expect(manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start + 2_200))
		// Then two hours.
		#expect(!manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start + 5_000))
		#expect(manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start + 9_500))
		// Then the twelve-hour cap, and it stays there.
		#expect(!manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start + 30_000))
		#expect(manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start + 53_000))
		#expect(!manager.shouldSurfaceFirmwareNotice(key: key, isSecurity: false, now: start + 80_000))
	}

	/// A standing notice settles to no more than a couple of alerts a day.
	@Test func chronicRepeatSettlesToTwiceADay() {
		let manager = AccessoryManager()
		let start = Date(timeIntervalSince1970: 2_000_000)
		var alerts = 0
		// Firmware repeating every three minutes for a day.
		for tick in stride(from: 0, through: 86_400, by: 180) {
			if manager.shouldSurfaceFirmwareNotice(key: "chatty", isSecurity: false, now: start + Double(tick)) {
				alerts += 1
			}
		}
		// Without backoff this would be 481.
		#expect(alerts <= 6, "expected a handful of alerts across a day, got \(alerts)")
		#expect(alerts >= 4, "the ladder should still let the early ones through, got \(alerts)")
	}

	@Test func distinctMessagesDoNotShareBackoff() {
		let manager = AccessoryManager()
		let start = Date(timeIntervalSince1970: 3_000_000)
		#expect(manager.shouldSurfaceFirmwareNotice(key: "a", isSecurity: false, now: start))
		// A different notice is unaffected by the first one's backoff.
		#expect(manager.shouldSurfaceFirmwareNotice(key: "b", isSecurity: false, now: start + 1))
	}

	@Test func securityNoticesNeverBackOff() {
		let manager = AccessoryManager()
		let start = Date(timeIntervalSince1970: 4_000_000)
		for tick in 0..<5 {
			#expect(manager.shouldSurfaceFirmwareNotice(
				key: "duplicatedPublicKey", isSecurity: true, now: start + Double(tick)
			))
		}
	}

	@Test func aQuietDayResetsTheLadder() {
		let manager = AccessoryManager()
		let start = Date(timeIntervalSince1970: 5_000_000)
		#expect(manager.shouldSurfaceFirmwareNotice(key: "seasonal", isSecurity: false, now: start))
		#expect(!manager.shouldSurfaceFirmwareNotice(key: "seasonal", isSecurity: false, now: start + 60))
		// Gone for more than a day: treated as fresh, so it alerts immediately again.
		let later = start + 90_000
		#expect(manager.shouldSurfaceFirmwareNotice(key: "seasonal", isSecurity: false, now: later))
		#expect(!manager.shouldSurfaceFirmwareNotice(key: "seasonal", isSecurity: false, now: later + 60))
	}

	@Test func keyPrefersTheStructuredVariant() {
		var withVariant = ClientNotification()
		withVariant.lowEntropyKey = LowEntropyKey()
		#expect(AccessoryManager.noticeKey(for: withVariant) == "lowEntropyKey")
		#expect(AccessoryManager.isSecurityNotice(withVariant))

		let plain = notice("Location sharing is disabled on this channel")
		#expect(AccessoryManager.noticeKey(for: plain).contains("Location sharing"))
		#expect(!AccessoryManager.isSecurityNotice(plain))
	}

	@Test func identifierFragmentIsBoundedAndSafe() {
		let fragment = AccessoryManager.noticeIdentifierFragment(
			"warning|Location sharing is disabled on this channel " + String(repeating: "x", count: 200)
		)
		#expect(fragment.count <= 64)
		#expect(!fragment.contains(" "))
		#expect(!fragment.contains("|"))
	}
}
