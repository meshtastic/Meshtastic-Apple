//
//  LockLegend.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 8/15/24.
//

import SwiftUI

struct LockLegend: View {

	var body: some View {
		Section {
			HelpItem(
				symbol: AnyView(
					Image(systemName: "person.badge.shield.checkmark")
						.font(.title3)
						.foregroundColor(.green)
				),
				title: String(localized: "Verified Contact"),
				subtitle: String(localized: "You verified this node's key in person, by exchanging contact QR codes. The strongest trust shown in the list. Nodes on firmware 2.8 or later show signing state instead of the locks.")
			)
			HelpItem(
				symbol: AnyView(
					Image("radio.badge.shield.checkmark")
						.font(.title3)
						.foregroundColor(.green)
				),
				title: String(localized: "Signed Node"),
				subtitle: String(localized: "The radio verified this node's signed broadcasts, so its identity is consistent over time, but you have not verified it in person.")
			)
			HelpItem(
				symbol: AnyView(
					Image(systemName: "lock.fill")
						.font(.title3)
						.foregroundColor(.green)
				),
				title: String(localized: "Public Key Encryption"),
				subtitle: String(localized: "Direct messages are using the public key infrastructure for encryption. Requires firmware version 2.5 or greater.")
			)
			HelpItem(
				symbol: AnyView(
					Image(systemName: "lock.open.fill")
						.font(.title3)
						.foregroundColor(.yellow)
				),
				title: String(localized: "Shared Key"),
				subtitle: String(localized: "Direct messages are using the shared key for the channel. Shown for nodes on firmware before 2.5.")
			)
			HelpItem(
				symbol: AnyView(
					Image(systemName: "key.slash")
						.font(.title3)
						.foregroundColor(.red)
				),
				title: String(localized: "Public Key Mismatch"),
				subtitle: String(localized: "The most recent public key for this node does not match the previously recorded key. Verify who you are messaging with by comparing public keys in person or over the phone. Shown at any firmware version.")
			)
		} header: {
			Text("Security")
		}
	}
}

struct LockLegendPreviews: PreviewProvider {
	static var previews: some View {
		List {
			LockLegend()
		}
	}
}
