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
		Text("This tool scans your local area to find nearby Meshtastic radios on different frequency settings. It switches between settings automatically, listens for a few minutes on each one, and then shows you which setting works best for your location based on how many radios it finds and how busy the airwaves are. On supported devices, local on-device AI will analyze your scan results and recommend the best setting — no internet connection required.")
	}
	var image: Image? {
		Image(systemName: "antenna.radiowaves.left.and.right")
	}
}
