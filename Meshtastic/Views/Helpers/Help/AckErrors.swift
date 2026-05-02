//
//  AckErrors.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 4/24/24.
//

import SwiftUI

struct AckErrors: View {

	var body: some View {
		Section {
			HelpItem(
				symbol: AnyView(
					RoundedRectangle(cornerRadius: 5)
						.fill(.orange)
						.frame(width: 20, height: 12)
				),
				title: String(localized: "Acknowledged by another node"),
				subtitle: String(localized: "Message was relayed but not confirmed by the final recipient."),
				compact: true
			)
			ForEach(RoutingError.allCases) { re in
				HelpItem(
					symbol: AnyView(
						RoundedRectangle(cornerRadius: 5)
							.fill(re.color)
							.frame(width: 20, height: 12)
					),
					title: re.display,
					subtitle: re.description,
					compact: true
				)
			}
		} header: {
			Text("Message Status")
		} footer: {
			Text("Grey indicates successful delivery. Orange indicates a retryable error. Red indicates a permanent failure that will not succeed on retry.")
		}
	}
}

struct AckErrorsPreviews: PreviewProvider {
	static var previews: some View {
		List {
			AckErrors()
		}
	}
}
