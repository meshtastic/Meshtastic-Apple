// MARK: PowerChannelLabelStoreTests
//
//  Covers the per-node power-channel label persistence (issue #2046): set/get, blank-clears,
//  whitespace trimming, per-node + per-channel keying, and default/display fallback.
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("PowerChannelLabelStore")
struct PowerChannelLabelStoreTests {

	private func makeDefaults(_ suiteName: String) -> UserDefaults {
		let defaults = UserDefaults(suiteName: suiteName)!
		defaults.removePersistentDomain(forName: suiteName)
		return defaults
	}

	@Test("A set label round-trips and drives the display label")
	func setAndGet() {
		let store = makeDefaults("PowerChannelLabel.setget")
		PowerChannelLabelStore.setLabel("Solar", nodeNum: 42, channel: 0, store: store)
		#expect(PowerChannelLabelStore.customLabel(nodeNum: 42, channel: 0, store: store) == "Solar")
		#expect(PowerChannelLabelStore.displayLabel(nodeNum: 42, channel: 0, store: store) == "Solar")
	}

	@Test("No label falls back to the default display label, not a custom one")
	func defaultFallback() {
		let store = makeDefaults("PowerChannelLabel.default")
		#expect(PowerChannelLabelStore.customLabel(nodeNum: 42, channel: 1, store: store) == nil)
		#expect(PowerChannelLabelStore.displayLabel(nodeNum: 42, channel: 1, store: store)
			== PowerChannelLabelStore.defaultLabel(channel: 1))
	}

	@Test("Setting nil or blank clears the override")
	func blankClears() {
		let store = makeDefaults("PowerChannelLabel.blank")
		PowerChannelLabelStore.setLabel("Battery", nodeNum: 42, channel: 2, store: store)
		#expect(PowerChannelLabelStore.customLabel(nodeNum: 42, channel: 2, store: store) == "Battery")

		PowerChannelLabelStore.setLabel("   ", nodeNum: 42, channel: 2, store: store)
		#expect(PowerChannelLabelStore.customLabel(nodeNum: 42, channel: 2, store: store) == nil)

		PowerChannelLabelStore.setLabel("Load", nodeNum: 42, channel: 2, store: store)
		PowerChannelLabelStore.setLabel(nil, nodeNum: 42, channel: 2, store: store)
		#expect(PowerChannelLabelStore.customLabel(nodeNum: 42, channel: 2, store: store) == nil)
	}

	@Test("Labels are trimmed of surrounding whitespace")
	func trimsWhitespace() {
		let store = makeDefaults("PowerChannelLabel.trim")
		PowerChannelLabelStore.setLabel("  Panel A  ", nodeNum: 7, channel: 0, store: store)
		#expect(PowerChannelLabelStore.customLabel(nodeNum: 7, channel: 0, store: store) == "Panel A")
	}

	@Test("Labels are scoped per node and per channel")
	func scopedPerNodeAndChannel() {
		let store = makeDefaults("PowerChannelLabel.scope")
		PowerChannelLabelStore.setLabel("Solar", nodeNum: 100, channel: 0, store: store)
		PowerChannelLabelStore.setLabel("Battery", nodeNum: 100, channel: 1, store: store)
		PowerChannelLabelStore.setLabel("Other", nodeNum: 200, channel: 0, store: store)

		#expect(PowerChannelLabelStore.customLabel(nodeNum: 100, channel: 0, store: store) == "Solar")
		#expect(PowerChannelLabelStore.customLabel(nodeNum: 100, channel: 1, store: store) == "Battery")
		#expect(PowerChannelLabelStore.customLabel(nodeNum: 200, channel: 0, store: store) == "Other")
		// A node/channel with no label set is unaffected.
		#expect(PowerChannelLabelStore.customLabel(nodeNum: 200, channel: 1, store: store) == nil)
	}
}
