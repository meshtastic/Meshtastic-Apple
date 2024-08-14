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

@available(iOS 17.0, macOS 14.0, *)
struct ContactsTip: Tip {

   var id: String {
	   return "tip.messages.contacts"
   }
   var title: Text {
	   // Text("tip.messages.contacts.title")
	   Text("Contacts")
   }
   var message: Text? {
	   // Text("tip.messages.contacts.message")
	   Text("Favorites and nodes with recent messages show up at the top of the list. Contacts using the shared key display an open lock, nodes with a private key show a green lock and a red key with a slash will show up if a key has changed for a contact. Long press to favorite or mute the contact or delete a conversation.")
   }
   var image: Image? {
	   Image(systemName: "person.circle")
   }
}
