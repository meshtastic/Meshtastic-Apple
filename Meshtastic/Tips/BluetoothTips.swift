//
//  BluetoothTips.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/31/23.
//
import SwiftUI
import TipKit

struct BluetoothConnectionTip: Tip {

	var id: String {
		return "tip.bluetooth.connect"
	}
	var title: Text {
		Text("Connected Radio")
	}
	var message: Text? {
		Text("Shows information for the Lora radio connected via bluetooth. You can swipe left to disconnect the radio and long press start the live activity.")
	}
	var image: Image? {
		Image(systemName: "flipphone")
	}
}
