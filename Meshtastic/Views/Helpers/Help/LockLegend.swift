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
				Text("Direct messages are using the new public key infrastructure for encryption. Reguires firmware version 2.5 or greater.")
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
				Text("The public key does not match the recorded key. You may delete the node and let it exchange keys again, but this may indicate a more serious security problem. Contact the user through another trusted channel, to determine if the key change was due to a factory reset or other intentional action.")
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
