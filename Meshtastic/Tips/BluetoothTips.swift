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
		Text("Swipe left to disconnect. Long press for more options.")
	}
	var image: Image? {
		Image("custom.mesh.radio")
	}
	var options: [TipOption] {
		Tips.IgnoresDisplayFrequency(true)
	}
}
