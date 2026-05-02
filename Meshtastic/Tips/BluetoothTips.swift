//
//  BluetoothTips.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/31/23.
//
import SwiftUI
import TipKit

struct ConnectionTip: Tip {

	var id: String {
		return "tip.connect"
	}
	var title: Text {
		Text("Connected Radio")
	}
	var message: Text? {
		Text("Swipe left to disconnect. Long press to start the live activity.")
	}
	var image: Image? {
		Image(systemName: "antenna.radiowaves.left.and.right")
	}
	var options: [TipOption] {
		Tips.IgnoresDisplayFrequency(true)
		Tips.MaxDisplayCount(3)
	}
}
