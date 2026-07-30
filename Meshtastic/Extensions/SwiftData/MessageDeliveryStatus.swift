import SwiftUI

struct MessageDeliveryStatus {
	let text: String
	let detail: String
	let systemImage: String
	let color: Color
	let canRetry: Bool

	static let sending = MessageDeliveryStatus(
		text: "Sending...".localized,
		detail: "Waiting for the mesh to acknowledge this message.".localized,
		systemImage: "clock",
		color: Color(uiColor: .systemOrange),
		canRetry: false
	)

	static let deliveredToMesh = MessageDeliveryStatus(
		text: "Delivered to mesh".localized,
		detail: "A node on the mesh confirmed this message.".localized,
		systemImage: "checkmark.circle.fill",
		color: Color(uiColor: .secondaryLabel),
		canRetry: false
	)

	static let relayedNotConfirmed = MessageDeliveryStatus(
		text: "Relayed, not confirmed by recipient".localized,
		detail: "A node relayed this message, but the recipient has not confirmed it.".localized,
		systemImage: "exclamationmark.circle.fill",
		color: Color(uiColor: .systemOrange),
		canRetry: true
	)

	/// Shown for an outgoing message that has gone unacknowledged past `MessageEntity.sendAckTimeout`
	/// — the radio's ack/nak never reached the app, so the message is stuck. Retryable, rather than an
	/// indefinite "Sending…". Reuses the max-retransmit detail wording: to the user the outcome is the
	/// same — the mesh never confirmed it.
	static let notDelivered = MessageDeliveryStatus(
		text: "Not delivered".localized,
		detail: "No node confirmed this message. Try again when you have better signal or more mesh coverage.".localized,
		systemImage: "exclamationmark.circle.fill",
		color: Color(uiColor: .systemOrange),
		canRetry: true
	)

	static let deliveredToRecipient = MessageDeliveryStatus(
		text: "Delivered to recipient".localized,
		detail: "The recipient confirmed this message.".localized,
		systemImage: "checkmark.circle.fill",
		color: Color(uiColor: .secondaryLabel),
		canRetry: false
	)

	static func failed(_ error: RoutingError) -> MessageDeliveryStatus {
		MessageDeliveryStatus(
			text: error.display,
			detail: error.description,
			systemImage: error.canRetry ? "exclamationmark.circle.fill" : "xmark.circle.fill",
			color: error.color,
			canRetry: error.canRetry
		)
	}
}

struct MessageDeliveryStatusLabel: View {
	let status: MessageDeliveryStatus

	var body: some View {
		Label {
			Text(status.text)
				.fixedSize(horizontal: false, vertical: true)
		} icon: {
			Image(systemName: status.systemImage)
				.imageScale(.small)
		}
		.font(.caption2)
		.foregroundStyle(status.color)
		.labelStyle(.titleAndIcon)
		.accessibilityLabel(status.text)
	}
}
