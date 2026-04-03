//
//  MessageTemplate.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/22.
//
import SwiftUI

struct MessageTemplate: View {

	var user: UserEntity
	var message: MessageEntity
	var messageReply: MessageEntity?

	var body: some View {

		// Display the message being replied to and the arrow
		if message.replyID > 0 {

			HStack {

				Text(messageReply?.messagePayload ?? "EMPTY MESSAGE").foregroundColor(.blue).font(.caption2)
					.padding(10)
					.overlay(
						RoundedRectangle(cornerRadius: 18)
							.stroke(Color.blue, lineWidth: 0.5)
				)
				Image(systemName: "arrowshape.turn.up.left.fill")
					.symbolRenderingMode(.hierarchical)
					.imageScale(.large).foregroundColor(.blue)
					.padding(.trailing)
			}
		}

		// Message

	}
}

#Preview {
	let context = PersistenceController.preview.container.viewContext
	let user = UserEntity(context: context)
	user.longName = "Test User"
	user.shortName = "TU"
	let message = MessageEntity(context: context)
	message.messagePayload = "Hello, World!"
	message.messageTimestamp = Int32(Date().timeIntervalSince1970)
	message.replyID = 0
	return MessageTemplate(user: user, message: message)
}