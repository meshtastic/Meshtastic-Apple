//
 //  ChannelTips.swift
 //  Meshtastic
 //
 //  Copyright(c) Garth Vander Houwen 8/31/23.
 //
 import SwiftUI
 #if canImport(TipKit)
 import TipKit
 #endif

 @available(iOS 17.0, macOS 14.0, *)
 struct ShareChannelsTip: Tip {

	var id: String {
		return "tip-channels-share"
	}
	var title: Text {
		Text("Sharing Meshtastic Channels")
	}

	var message: Text? {
		Text("In a Meshtastic LoRa Mesh there are up to 8 channels. The first one is the Primary channel where most activity happens and is required. If you don't share your primary channel your first shared channel becomes the primary channel on the other network. It talks on its primary and your secondary channel. A channel with the name 'admin' controls nodes remotely. Other channels are for private groups, each with its own key.")
	}

	var image: Image? {
		Image(systemName: "questionmark.circle")
	}
 }
