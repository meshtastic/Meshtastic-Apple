//
//  AddContactConfirmationView.swift
//  Meshtastic
//
//  SwiftUI confirmation sheet for importing a contact from a
//  meshtastic.org/v/# URL (QR code, shared link, or NFC tag).
//

import SwiftUI
import MeshtasticProtobufs
import OSLog

struct AddContactConfirmationView: View {
	let pendingContact: PendingContact
	var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var dismiss

	private var shortName: String {
		let name = pendingContact.contact.user.shortName
		return name.isEmpty ? "?" : name
	}

	var body: some View {
		VStack(spacing: 20) {
			Text("Add Contact")
				.font(.title2)
				.padding(.top)
			CircleText(
				text: shortName,
				color: Color(UIColor(hex: UInt32(pendingContact.contact.nodeNum))),
				circleSize: 60
			)
			Text(pendingContact.contact.user.longName)
				.font(.headline)
			Text("Adding a contact saves their name and public key to your connected node so you can message them securely.")
				.font(.subheadline)
				.multilineTextAlignment(.center)
				.foregroundColor(.secondary)
			Button {
				let base64UrlString = pendingContact.base64UrlString
				Task {
					do {
						try await accessoryManager.addContactFromURL(base64UrlString: base64UrlString)
						Logger.services.debug("Contact added from URL successfully")
					} catch {
						Logger.services.error("Contact added from URL failed with error \(error.localizedDescription, privacy: .public)")
					}
				}
				dismiss()
			} label: {
				Label("Add Contact", systemImage: "person.crop.circle.badge.plus")
			}
			.buttonStyle(.borderedProminent)
			Button("Cancel") { dismiss() }
				.padding(.bottom)
		}
		.padding()
		.frame(maxWidth: 350)
	}
}

#if DEBUG
struct AddContactConfirmationView_Previews: PreviewProvider {
	static var previews: some View {
		var contact = SharedContact()
		contact.nodeNum = 123456
		var userProto = User()
		userProto.id = "!1234"
		userProto.longName = "Bud"
		userProto.shortName = "Bud"
		contact.user = userProto

		return AddContactConfirmationView(
			pendingContact: PendingContact(contact: contact, base64UrlString: ""),
			accessoryManager: AccessoryManager.shared
		)
	}
}
#endif
