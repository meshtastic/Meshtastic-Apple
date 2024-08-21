//
//  MessagesTips.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/15/23.
//
import SwiftUI
#if canImport(TipKit)
import TipKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct MessagesTip: Tip {

   var id: String {
	   return "tip.messages"
   }
   var title: Text {
	   Text("tip.messages.title")
   }
   var message: Text? {
	   Text("tip.messages.message")
   }
   var image: Image? {
	   Image(systemName: "bubble.left.and.bubble.right")
   }
}
