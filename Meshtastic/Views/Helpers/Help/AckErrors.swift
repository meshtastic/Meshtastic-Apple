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
					Image(systemName: MessageDeliveryStatus.sending.systemImage)
						.foregroundStyle(MessageDeliveryStatus.sending.color)
						.frame(width: 20)
				),
				title: MessageDeliveryStatus.sending.text,
				subtitle: MessageDeliveryStatus.sending.detail,
				compact: true
			)
			HelpItem(
				symbol: AnyView(
					Image(systemName: MessageDeliveryStatus.deliveredToMesh.systemImage)
						.foregroundStyle(MessageDeliveryStatus.deliveredToMesh.color)
						.frame(width: 20)
				),
				title: MessageDeliveryStatus.deliveredToMesh.text,
				subtitle: MessageDeliveryStatus.deliveredToMesh.detail,
				compact: true
			)
			HelpItem(
				symbol: AnyView(
					Image(systemName: MessageDeliveryStatus.relayedNotConfirmed.systemImage)
						.foregroundStyle(MessageDeliveryStatus.relayedNotConfirmed.color)
						.frame(width: 20)
				),
				title: MessageDeliveryStatus.relayedNotConfirmed.text,
				subtitle: MessageDeliveryStatus.relayedNotConfirmed.detail,
				compact: true
			)
			HelpItem(
				symbol: AnyView(
					Image(systemName: MessageDeliveryStatus.deliveredToRecipient.systemImage)
						.foregroundStyle(MessageDeliveryStatus.deliveredToRecipient.color)
						.frame(width: 20)
				),
				title: MessageDeliveryStatus.deliveredToRecipient.text,
				subtitle: MessageDeliveryStatus.deliveredToRecipient.detail,
				compact: true
			)
			ForEach(RoutingError.allCases.filter { $0 != .none }) { re in
				HelpItem(
					symbol: AnyView(
						Image(systemName: re.canRetry ? "exclamationmark.circle.fill" : "xmark.circle.fill")
							.foregroundStyle(re.color)
							.frame(width: 20)
					),
					title: re.display,
					subtitle: re.description,
					compact: true
				)
			}
		} header: {
			Text("Message Status")
		} footer: {
			Text("Text is shown with icon and color. Gray indicates delivery, orange indicates sending or a retryable warning, and red indicates a permanent failure that will not succeed on retry.")
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
