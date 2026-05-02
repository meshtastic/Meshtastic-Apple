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
					Image(systemName: "lock.open.fill")
						.font(.title3)
						.foregroundColor(.yellow)
				),
				title: String(localized: "Shared Key"),
				subtitle: String(localized: "Direct messages are using the shared key for the channel.")
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
					Image(systemName: "key.slash")
						.font(.title3)
						.foregroundColor(.red)
				),
				title: String(localized: "Public Key Mismatch"),
				subtitle: String(localized: "The most recent public key for this node does not match the previously recorded key. Verify who you are messaging with by comparing public keys in person or over the phone.")
			)
		} header: {
			Text("Encryption")
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
