//
//  AddContactConfirmationView.swift
//  Meshtastic
//
//  SwiftUI confirmation sheet for importing a contact from a
//  meshtastic.org/v/# URL (QR code, shared link, or NFC tag).
//

import SwiftUI
import UIKit
import MeshtasticProtobufs
import OSLog

struct AddContactConfirmationView: View {
	let pendingContact: PendingContact
	let accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var dismiss
	@State private var isAdding = false
	@State private var failureMessage: String?
	@State private var replyShareItem: ContactReplyShareItem?

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
			if let failureMessage {
				Text(failureMessage)
					.font(.subheadline)
					.multilineTextAlignment(.center)
					.foregroundColor(.red)
			}
			if pendingContact.exchangeRequested {
				Text("They asked to exchange contacts. You can add theirs and immediately share your recently connected radio's contact back.")
					.font(.subheadline)
					.multilineTextAlignment(.center)
					.foregroundColor(.secondary)
				Button {
					addContact(replyAfterAdding: true)
				} label: {
					Label("Add & Share Mine", systemImage: "arrow.left.arrow.right.circle.fill")
				}
				.buttonStyle(.borderedProminent)
				.disabled(isAdding || MeshShareStore.load() == nil)
				Button {
					addContact()
				} label: {
					Label("Just Add Contact", systemImage: "person.crop.circle.badge.plus")
				}
				.buttonStyle(.bordered)
				.disabled(isAdding)
			} else {
				Button {
					addContact()
				} label: {
					Label("Add Contact", systemImage: "person.crop.circle.badge.plus")
				}
				.buttonStyle(.borderedProminent)
				.disabled(isAdding)
			}
			Button("Cancel") { dismiss() }
				.padding(.bottom)
		}
		.padding()
		.frame(maxWidth: 350)
		.sheet(item: $replyShareItem, onDismiss: { dismiss() }) { item in
			ContactReplyActivityView(url: item.url)
		}
	}

	/// Imports the contact, dismissing only once it actually succeeds so a
	/// failure leaves the sheet up with an explanation and a retry path.
	///
	/// `@MainActor` so the task inherits main-actor isolation: the `@State`
	/// mutations and `dismiss()` below then run on the main actor rather than
	/// whatever executor the task would otherwise pick up.
	@MainActor
	private func addContact(replyAfterAdding: Bool = false) {
		let base64UrlString = pendingContact.base64UrlString
		isAdding = true
		failureMessage = nil
		Task {
			do {
				try await accessoryManager.addContactFromURL(base64UrlString: base64UrlString)
				Logger.services.debug("Contact added from URL successfully")
				if replyAfterAdding,
				   let snapshot = MeshShareStore.load(),
				   let url = URL(string: snapshot.contactReplyURL) {
					replyShareItem = ContactReplyShareItem(url: url)
				} else {
					dismiss()
				}
			} catch {
				Logger.services.error("Contact added from URL failed with error \(error.localizedDescription, privacy: .public)")
				failureMessage = String(localized: "Couldn't add this contact. Check that your node is connected and try again.")
				isAdding = false
			}
		}
	}
}

private struct ContactReplyShareItem: Identifiable {
	let id = UUID()
	let url: URL
}

private struct ContactReplyActivityView: UIViewControllerRepresentable {
	let url: URL

	func makeUIViewController(context: Context) -> UIActivityViewController {
		UIActivityViewController(
			activityItems: [
				"Here's my Meshtastic contact — let's stay connected on the mesh.",
				url
			],
			applicationActivities: nil
		)
	}

	func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
			pendingContact: PendingContact(
				contact: contact,
				base64UrlString: "",
				exchangeRequested: true
			),
			accessoryManager: AccessoryManager.shared
		)
	}
}
#endif
