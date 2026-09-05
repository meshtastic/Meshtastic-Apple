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
	let accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var dismiss
	@State private var isAdding = false
	@State private var failureMessage: String?

	private var shortName: String {
		let name = pendingContact.contact.user.shortName
		return name.isEmpty ? "?" : name
	}

	/// A contact with no public key would clear the key the node already holds, so there is
	/// nothing safe to import. See `SharedContact.carriesPublicKey`.
	private var canAdd: Bool {
		pendingContact.contact.carriesPublicKey
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
			if !canAdd {
				Text("This contact does not include a public key, so it cannot be added.")
					.font(.subheadline)
					.multilineTextAlignment(.center)
					.foregroundColor(.red)
			}
			if let failureMessage {
				Text(failureMessage)
					.font(.subheadline)
					.multilineTextAlignment(.center)
					.foregroundColor(.red)
			}
			Button {
				addContact()
			} label: {
				Label("Add Contact", systemImage: "person.crop.circle.badge.plus")
			}
			.buttonStyle(.borderedProminent)
			.disabled(isAdding || !canAdd)
			Button("Cancel") { dismiss() }
				.padding(.bottom)
		}
		.padding()
		.frame(maxWidth: 350)
	}

	/// Imports the contact, dismissing only once it actually succeeds so a
	/// failure leaves the sheet up with an explanation and a retry path.
	///
	/// `@MainActor` so the task inherits main-actor isolation: the `@State`
	/// mutations and `dismiss()` below then run on the main actor rather than
	/// whatever executor the task would otherwise pick up.
	@MainActor
	private func addContact() {
		let base64UrlString = pendingContact.base64UrlString
		isAdding = true
		failureMessage = nil
		Task {
			do {
				try await accessoryManager.addContactFromURL(base64UrlString: base64UrlString)
				Logger.services.debug("Contact added from URL successfully")
				dismiss()
			} catch {
				Logger.services.error("Contact added from URL failed with error \(error.localizedDescription, privacy: .public)")
				failureMessage = String(localized: "Couldn't add this contact. Check that your node is connected and try again.")
				isAdding = false
			}
		}
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
