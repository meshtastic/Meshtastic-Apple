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
		Text("tip.channels.share.title")
	}
	var message: Text? {
		Text("tip.channels.share.message")
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
	   Text("tip.channels.create.title")
   }
   var message: Text? {
	   Text("tip.channels.create.message")
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
