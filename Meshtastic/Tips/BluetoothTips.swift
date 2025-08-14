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
		Text("Shows information for the connected Lora radio. You can swipe left to disconnect the radio and long press to start the live activity.")
	}
	var image: Image? {
		Image(systemName: "flipphone")
	}
}
