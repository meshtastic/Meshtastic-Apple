//
//  MessagesTips.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/15/23.
//
import SwiftUI
import TipKit

struct MessagesTip: Tip {

   var id: String {
	   return "tip.messages"
   }
   var title: Text {
	   Text("Messages")
   }
   var message: Text? {
	   Text("tip.messages.message")
   }
   var image: Image? {
	   Image(systemName: "bubble.left.and.bubble.right")
   }
}
