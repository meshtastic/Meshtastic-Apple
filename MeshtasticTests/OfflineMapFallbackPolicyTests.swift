//
//  OfflineMapFallbackPolicyTests.swift
//  MeshtasticTests
//

import Testing

@testable import Meshtastic

@Suite("Offline map fallback policy")
struct OfflineMapFallbackPolicyTests {
	@Test func disabledPreferenceFallsBackWithoutNetworkWhenMapsExist() {
		#expect(OfflineMapFallbackPolicy.shouldRenderOfflineMaps(
			userEnabled: false,
			hasSavedMaps: true,
			networkAvailable: false
		))
	}

	@Test func disabledPreferenceDoesNotRenderWhileOnline() {
		#expect(!OfflineMapFallbackPolicy.shouldRenderOfflineMaps(
			userEnabled: false,
			hasSavedMaps: true,
			networkAvailable: true
		))
	}

	@Test func enabledPreferenceRendersWithoutSavedMaps() {
		#expect(OfflineMapFallbackPolicy.shouldRenderOfflineMaps(
			userEnabled: true,
			hasSavedMaps: false,
			networkAvailable: true
		))
	}

	@Test func noMapsDoesNotCreateAnOfflineFallback() {
		#expect(!OfflineMapFallbackPolicy.shouldRenderOfflineMaps(
			userEnabled: false,
			hasSavedMaps: false,
			networkAvailable: false
		))
	}
}
