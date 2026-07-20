//
//  BurningManOfflinePackTests.swift
//  MeshtasticTests
//

import CoreLocation
import Foundation
import Testing

@testable import Meshtastic

@Suite("Burning Man offline pack policy")
struct BurningManOfflinePackTests {

	@Test func outsideAreaOnSeptember8_removesPack() {
		let action = BurningManOfflinePack.policy(
			now: .burningMan("2026-09-08T08:00:00Z"),
			location: CLLocation(
				coordinate: .init(latitude: 37.3346, longitude: -122.0090), altitude: 0,
				horizontalAccuracy: 30, verticalAccuracy: 30,
				timestamp: .burningMan("2026-09-08T07:00:00Z")
			)
		)
		#expect(action == .remove)
	}

	@Test func noLocationBeforeSeptember12_retainsPack() {
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-10T08:00:00Z"), location: nil
		) == .retain)
	}

	@Test func noLocationOnSeptember12_removesPack() {
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-12T07:00:00Z"), location: nil
		) == .remove)
	}

	@Test func recentLocationInsideBufferedArea_retainsPack() {
		let location = CLLocation(
			coordinate: .init(latitude: 40.7800, longitude: -119.2000), altitude: 0,
			horizontalAccuracy: 30, verticalAccuracy: 30,
			timestamp: .burningMan("2026-09-10T07:00:00Z")
		)
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-10T08:00:00Z"), location: location
		) == .retain)
	}

	@Test func staleLocationBeforeSeptember12_retainsPack() {
		let location = CLLocation(
			coordinate: .init(latitude: 37.3346, longitude: -122.0090), altitude: 0,
			horizontalAccuracy: 30, verticalAccuracy: 30,
			timestamp: .burningMan("2026-09-08T07:59:59Z")
		)
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-10T08:00:00Z"), location: location
		) == .retain)
	}

	@Test func invalidAccuracyBeforeSeptember12_retainsPack() {
		let location = CLLocation(
			coordinate: .init(latitude: 37.3346, longitude: -122.0090), altitude: 0,
			horizontalAccuracy: -1, verticalAccuracy: -1,
			timestamp: .burningMan("2026-09-10T07:00:00Z")
		)
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-10T08:00:00Z"), location: location
		) == .retain)
	}
}

private extension Date {
	static func burningMan(_ value: String) -> Date {
		ISO8601DateFormatter().date(from: value)!
	}
}
