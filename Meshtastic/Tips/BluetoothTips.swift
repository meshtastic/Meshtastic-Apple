//
//  BluetoothTips.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/31/23.
//
import SwiftUI
#if canImport(TipKit)
import TipKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct BluetoothConnectionTip: Tip {

	var id: String {
		return "tip.bluetooth.connect"
	}
	var title: Text {
		Text("tip.bluetooth.connect.title")
	}
	var message: Text? {
		Text("tip.bluetooth.connect.message")
	}
	var image: Image? {
		Image(systemName: "questionmark.circle")
	}
}
