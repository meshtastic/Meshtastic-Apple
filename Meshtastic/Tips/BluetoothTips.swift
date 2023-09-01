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
		return "tip-bluetooth-connect"
	}
	var title: Text {
		Text("Connected LoRa Radio Info")
	}

	var message: Text? {
		Text("Shows information for the Lora radio currently connected via bluetooth. You can swipe left to disconnect the radio and long press to view stats or start the live activity.")
	}

	var image: Image? {
		Image(systemName: "questionmark.circle")
	}
}
