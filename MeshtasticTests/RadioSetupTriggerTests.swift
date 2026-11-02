//
//  RadioSetupTriggerTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("RadioSetupTrigger")
struct RadioSetupTriggerTests {

	/// A connected radio with no region and nothing in the way.
	private func trigger(
		nodeNum: Int64? = 1,
		regionCode: Int? = RegionCodes.unset.rawValue,
		offered: Set<Int64> = [],
		isSubscribed: Bool = true,
		isFirstLaunchFlowShowing: Bool = false,
		isLockdownBlocking: Bool = false,
		isFirmwareGateActive: Bool = false,
		isDatabaseResetting: Bool = false
	) -> RadioSetupTrigger {
		RadioSetupTrigger(
			nodeNum: nodeNum, regionCode: regionCode, offered: offered, isSubscribed: isSubscribed,
			isFirstLaunchFlowShowing: isFirstLaunchFlowShowing, isLockdownBlocking: isLockdownBlocking,
			isFirmwareGateActive: isFirmwareGateActive, isDatabaseResetting: isDatabaseResetting)
	}

	@Test func opensForAnUnsetRegionOnce() {
		#expect(trigger().shouldPresent)
		#expect(!trigger(offered: [1]).shouldPresent)
		#expect(trigger(offered: [2]).shouldPresent)
	}

	@Test func staysClosedOnceARegionIsSet() {
		#expect(!trigger(regionCode: RegionCodes.us.rawValue).shouldPresent)
	}

	@Test func waitsForTheConfigAndTheSubscription() {
		#expect(!trigger(regionCode: nil).shouldPresent)
		#expect(!trigger(isSubscribed: false).shouldPresent)
		#expect(!trigger(nodeNum: nil).shouldPresent)
	}

	@Test func yieldsToTheGates() {
		#expect(!trigger(isFirstLaunchFlowShowing: true).shouldPresent)
		#expect(!trigger(isLockdownBlocking: true).shouldPresent)
		#expect(!trigger(isFirmwareGateActive: true).shouldPresent)
		#expect(!trigger(isDatabaseResetting: true).shouldPresent)
	}
}

@Suite("RadioSetup offered radios", .serialized)
struct RadioSetupOfferedTests {

	@Test func aRadioIsRecordedOnce() {
		UserDefaults.radioSetupOfferedNodeNums = []
		defer { UserDefaults.radioSetupOfferedNodeNums = [] }
		#expect(!UserDefaults.radioSetupOfferedNodeNumSet.contains(42))
		UserDefaults.markRadioSetupOffered(nodeNum: 42)
		UserDefaults.markRadioSetupOffered(nodeNum: 42)
		UserDefaults.markRadioSetupOffered(nodeNum: 7)
		#expect(UserDefaults.radioSetupOfferedNodeNums == [7, 42])
		#expect(UserDefaults.radioSetupOfferedNodeNumSet == [7, 42])
	}
}
