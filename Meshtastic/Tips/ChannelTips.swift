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
		Text("Share Channels")
	}
	var message: Text? {
		Text("A QR code contains the LoRa config and channels needed for radios to communicate. Use Replace Channels to overwrite or Add Channels to append to existing channels.")
	}
	var image: Image? {
		Image(systemName: "qrcode")
	}
	var options: [TipOption] {
		Tips.IgnoresDisplayFrequency(true)
		Tips.MaxDisplayCount(3)
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
	   Text("The primary channel handles broadcast traffic. Add secondary channels for separate messaging groups, each secured by their own key. [Learn more](https://meshtastic.org/docs/configuration/tips/)")
   }
   var image: Image? {
	   Image(systemName: "lock.shield")
   }
   var options: [TipOption] {
	   Tips.IgnoresDisplayFrequency(true)
	   Tips.MaxDisplayCount(3)
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
	   Image(systemName: "gearshape.arrow.triangle.2.circlepath")
   }
   var options: [TipOption] {
	   Tips.IgnoresDisplayFrequency(true)
	   Tips.MaxDisplayCount(3)
   }
}
