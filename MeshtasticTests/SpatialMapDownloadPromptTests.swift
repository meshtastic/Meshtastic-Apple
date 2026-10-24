//
//  SpatialMapDownloadPromptTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
import Testing
@testable import Meshtastic

@Suite("Spatial map download prompt")
struct SpatialMapDownloadPromptTests {
	private func offers(_ prompt: inout SpatialMapDownloadPrompt, refreshes: Int, positionedNodes: Int = 0, autoDownload: Bool = true, isBusy: Bool = false) -> [Bool] {
		(0..<refreshes).map { _ in prompt.shouldOffer(positionedNodes: positionedNodes, autoDownload: autoDownload, isBusy: isBusy) }
	}

	@Test func offersOnceAfterTheSettleWithNoPositions() {
		var prompt = SpatialMapDownloadPrompt()
		let results = offers(&prompt, refreshes: SpatialMapDownloadPrompt.settleRefreshes + 3)
		#expect(results.filter { $0 }.count == 1)
		#expect(results[SpatialMapDownloadPrompt.settleRefreshes - 1])
	}

	@Test func neverOffersOncePositionsArrive() {
		var prompt = SpatialMapDownloadPrompt()
		_ = offers(&prompt, refreshes: 1)
		_ = offers(&prompt, refreshes: 1, positionedNodes: 3)
		let later = offers(&prompt, refreshes: 10)
		#expect(!later.contains(true))
	}

	@Test func waitsWhileTheAutomaticDownloadIsOff() {
		var prompt = SpatialMapDownloadPrompt()
		#expect(!offers(&prompt, refreshes: 10, autoDownload: false).contains(true))
	}

	@Test func waitsWhileADownloadIsRunning() {
		var prompt = SpatialMapDownloadPrompt()
		#expect(!offers(&prompt, refreshes: 10, isBusy: true).contains(true))
		let shouldOffer = prompt.shouldOffer(positionedNodes: 0, autoDownload: true, isBusy: false)
		#expect(shouldOffer)
	}
}
