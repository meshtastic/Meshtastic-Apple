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
			Text("Node Encryption Status")
				.font(.title2)
			Text("What does the lock mean?")
				.padding(.bottom)
			VStack(alignment: .leading) {
				HStack {
					Image(systemName: "lock.open.fill")
						.foregroundColor(.yellow)
					Text("Shared Key")
						.fontWeight(.semibold)
				}
				Text("Direct messages are using the shared key for the channel when communicating with this node.")
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
				Text("Direct messages are using the new public key infrastructure to encrypt the message.")
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
				Text("The public key does not match the key that was used previously, delete the node and let it negotatiate keys again. Usually the other user did a factory reset, but it could indicate a security issue.")
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
