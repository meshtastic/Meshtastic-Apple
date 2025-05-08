//
 //  ChannelTips.swift
 //  Meshtastic
 //
 //  Copyright(c) Garth Vander Houwen 8/31/23.
 //
 import SwiftUI
 import TipKit

 struct ShareChannelsTip: Tip {

	var id: String {
		return "tip.channels.share"
	}
	var title: Text {
		Text("Sharing Meshtastic Channels")
	}
	var message: Text? {
		Text("A Meshtastic QR code contains the LoRa config and channel values needed for radios to communicate. You can share a complete channel configuration using the Replace Channels option, if you choose Add Channels your shared channels will be added to the channels on the receiving radio.")
	}
	var image: Image? {
		Image(systemName: "qrcode")
	}
 }

struct CreateChannelsTip: Tip {

   var id: String {
	   return "tip.channels.create"
   }
   var title: Text {
	   Text("Manage Channels")
   }
   var message: Text? {
	   Text("Most data on your mesh is sent over the primary channel. You can set up secondary channels to create additional messaging groups secured by their own key. [Channel config tips](https://meshtastic.org/docs/configuration/tips/)")
   }
   var image: Image? {
	   Image(systemName: "fibrechannel")
   }
}

struct AdminChannelTip: Tip {

   var id: String {
	   return "tip.channel.admin"
   }
   var title: Text {
	   Text("Administration Enabled")
   }
   var message: Text? {
	   Text("Select a node from the drop down to manage connected or remote devices.")
   }
   var image: Image? {
	   Image(systemName: "fibrechannel")
   }
}
