//
//  LockLegend.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 8/15/24.
//

import SwiftUI

struct LockLegend: View {

	var body: some View {
		VStack(alignment: .leading) {
			Text("What does the lock mean?")
				.font(.title2)
				.padding(.bottom, 5)
			VStack(alignment: .leading) {
				HStack {
					Image(systemName: "lock.open.fill")
						.foregroundColor(.yellow)
					Text("Shared Key")
						.fontWeight(.semibold)
				}
				Text("Direct messages are using the shared key for the channel.")
					.allowsTightening(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
					.font(.callout)
					.fixedSize(horizontal: false, vertical: true)
			}
			.padding(.bottom)
			VStack(alignment: .leading) {
				HStack {
					Image(systemName: "lock.fill")
						.foregroundColor(.green)
					Text("Public Key Encryption")
						.fontWeight(.semibold)
				}
				Text("Direct messages are using the new public key infrastructure for encryption. Requires firmware version 2.5 or greater.")
					.allowsTightening(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
					.font(.callout)
					.fixedSize(horizontal: false, vertical: true)
			}
			.padding(.bottom)
			VStack(alignment: .leading) {
				HStack {
					Image(systemName: "key.slash")
						.foregroundColor(.red)
					Text("Public Key Mismatch")
						.fontWeight(.semibold)
				}
				Text("Verify who you are messaging with by comparing public keys in person or over the phone. The most recent public key for this node does not match the previously recorded key. You can delete the node and let it exchange keys again if the key change was due to a factory reset or other intentional action but this also may indicate a more serious security problem.")
					.allowsTightening(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
					.font(.callout)
					.fixedSize(horizontal: false, vertical: true)
			}
			.padding(.bottom)
		}
	}
}

struct LockLegendPreviews: PreviewProvider {
	static var previews: some View {
		VStack {
			LockLegend()
		}
	}
}
