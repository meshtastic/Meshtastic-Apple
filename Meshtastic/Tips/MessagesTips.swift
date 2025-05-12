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
	   Text("You can send and receive channel (group chats) and direct messages.  From any message you can long press to see available actions like copy, reply, tapback and delete as well as delivery details.")
   }
   var image: Image? {
	   Image(systemName: "bubble.left.and.bubble.right")
   }
}
