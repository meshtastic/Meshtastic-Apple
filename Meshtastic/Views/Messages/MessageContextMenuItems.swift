import SwiftUI
import CoreData
import OSLog

struct MessageContextMenuItems: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	let message: MessageEntity
	let tapBackDestination: MessageDestination
	let isCurrentUser: Bool
	@Binding var isShowingDeleteConfirmation: Bool
	@Binding var isShowingTapbackInput: Bool
	let onReply: () -> Void
	@State var relayDisplay: String? = nil

	var body: some View {
		VStack {
			if message.pkiEncrypted {
				Label("Encrypted", systemImage: "lock")
			}
			Text("Channel") + Text(": \(message.channel)")
		}
		.onAppear {
			DispatchQueue.global(qos: .userInitiated).async {
				let result = message.relayDisplay()
				DispatchQueue.main.async {
					relayDisplay = result
				}
			}
		}

		Button("Tapback") {
			isShowingTapbackInput = true
		}

		Button(action: onReply) {
			Text("Reply")
			Image(systemName: "arrowshape.turn.up.left")
		}

		Button {
			UIPasteboard.general.string = message.messagePayload
		} label: {
			Text("Copy")
			Image(systemName: "doc.on.doc")
		}

		Menu("Message Details") {
			// Precompute values to avoid executing non-View code inside the ViewBuilder
			let messageDate = Date(timeIntervalSince1970: TimeInterval(message.messageTimestamp))
			let ackDate = Date(timeIntervalSince1970: TimeInterval(message.ackTimestamp))
			let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())

			// Compute a relay display string if relayNode is present
			

			VStack {
				Text("\(messageDate.formattedDate(format: MessageText.dateFormatString))")
					.foregroundColor(.gray)
			}

			if let relayDisplay {
				let prefix = message.realACK ? "Ack Relay: " : "Relay: "
				Text(prefix + relayDisplay)
					.foregroundColor(relayDisplay.contains("Node ") ? .gray : .primary)
					.font(relayDisplay.contains("Node ") ? .caption : .body)
			}

			if !isCurrentUser && !(message.fromUser?.userNode?.viaMqtt ?? false) && message.fromUser?.userNode?.hopsAway ?? -1 == 0 {
				VStack {
					Text("SNR \(String(format: "%.2f", message.snr)) dB")
					Text("RSSI \(String(format: "%.2f", message.rssi)) dBm")
				}
			} else if !isCurrentUser && !(message.fromUser?.userNode?.viaMqtt ?? false) {
				VStack {
					Text("Hops Away \(message.fromUser?.userNode?.hopsAway ?? 0)")
				}
			}
			if message.relays != 0 && message.realACK == false {
				Text("Relayed by \(message.relays) \(message.relays == 1 ? "node" : "nodes")")
			}
			if isCurrentUser && message.receivedACK {
				VStack {
					Text("Received Ack: \(message.receivedACK ? "✔️" : "")")
					Text("Recipient Ack: \(message.realACK ? "✔️" : "")")
				}
			} else if isCurrentUser && message.ackError == 0 {
				Text("Waiting")
			} else if isCurrentUser && message.ackError > 0 {
				let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
				Text("\(ackErrorVal?.display ?? "Empty Ack Error")")
					.fixedSize(horizontal: false, vertical: true)
			}

			if isCurrentUser {
				if let sixMonthsAgo, ackDate >= sixMonthsAgo {
					Text("Ack Time: \(ackDate.formattedDate(format: MessageText.timeFormatString))")
						.foregroundColor(.gray)
				}
			}

			if message.ackSNR != 0 {
				VStack {
					Text("Ack SNR: \(String(format: "%.2f", message.ackSNR)) dB")
						.font(.caption2)
						.foregroundColor(.gray)
				}
			}
		}

		Divider()

		Button(role: .destructive) {
			isShowingDeleteConfirmation = true
		} label: {
			Text("Delete")
			Image(systemName: "trash")
		}
	}
}

private extension MessageDestination {
	var managedObject: NSManagedObject {
		switch self {
		case let .user(user): return user
		case let .channel(channel): return channel
		}
	}
}
