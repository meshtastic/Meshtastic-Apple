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
		return "tip.channels.share"
	}
	var title: Text {
		Text("tip.channels.share.title")
	}
	var message: Text? {
		Text("tip.channels.share.message")
	}
	var image: Image? {
		Image(systemName: "questionmark.circle")
	}
 }
