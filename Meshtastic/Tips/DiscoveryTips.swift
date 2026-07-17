// MARK: DiscoveryTips
//
//  DiscoveryTips.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import SwiftUI
import TipKit

struct DiscoveryScanTip: Tip {

	var id: String {
		return "tip.discovery.scan"
	}
	var title: Text {
		Text("What does this do?")
	}
	var message: Text? {
		Text("Scans nearby frequency settings and recommends the best one for your area — on-device, no internet required.")
	}
	var image: Image? {
		Image(systemName: "antenna.radiowaves.left.and.right")
	}
}
