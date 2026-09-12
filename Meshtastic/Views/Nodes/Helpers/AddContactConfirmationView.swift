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
	@State private var hasShareableSnapshot = false
	@State private var confirmsInPersonExchange = false

	private var shortName: String {
		let name = pendingContact.contact.user.shortName
		return name.isEmpty ? "?" : name
	}

	/// A contact with no public key would clear the key the node already holds, so there is
	/// nothing safe to import. See `SharedContact.carriesPublicKey`.
	private var canAdd: Bool {
		pendingContact.contact.carriesPublicKey
	}

	/// The shared contact claims it was exchanged in person. Anyone can put that bit in a link,
	/// so the claim only stands if the person importing it attests to the exchange; otherwise it
	/// is stripped before the contact goes to the radio.
	private var claimsInPersonExchange: Bool {
		pendingContact.contact.manuallyVerified
	}

	var body: some View {
		VStack(spacing: 20) {
			Text("Add Contact")
				.font(.title2)
				.padding(.top)
			HStack(spacing: 12) {
				CircleText(
					text: shortName,
					color: Color(UIColor(hex: UInt32(pendingContact.contact.nodeNum))),
					circleSize: 60
				)
				Text(pendingContact.contact.user.longName)
					.font(.headline)
					.fixedSize(horizontal: false, vertical: true)
			}
			Text("Adding a contact saves their name and public key to your connected node so you can message them securely.")
				.font(.subheadline)
				.multilineTextAlignment(.center)
				.foregroundColor(.secondary)
				// The sheet's medium detent compresses flexible text into an ellipsis even with
				// room left in the sheet. Fixed vertical size keeps every line.
				.fixedSize(horizontal: false, vertical: true)
			if claimsInPersonExchange && canAdd {
				VStack(alignment: .leading, spacing: 8) {
					Toggle(isOn: $confirmsInPersonExchange) {
						Label {
							Text("Verified in person")
								.font(.footnote.weight(.medium))
						} icon: {
							VerifiedContactIcon.image
								.foregroundStyle(confirmsInPersonExchange ? .green : .secondary)
						}
					}
					.tint(.green)
					Text("This contact says it was handed to you directly. It is added either way — confirm only if that is true.")
						.font(.caption2)
						.foregroundColor(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(16)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			if !canAdd {
				Text("This contact does not include a public key, so it cannot be added.")
					.font(.subheadline)
					.multilineTextAlignment(.center)
					.foregroundColor(.red)
					.fixedSize(horizontal: false, vertical: true)
			}
			if let failureMessage {
				Text(failureMessage)
					.font(.subheadline)
					.multilineTextAlignment(.center)
					.foregroundColor(.red)
					.fixedSize(horizontal: false, vertical: true)
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
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(isAdding || !canAdd || !hasShareableSnapshot)
				Button {
					addContact()
				} label: {
					Label("Just Add Contact", systemImage: "person.crop.circle.badge.plus")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
				.controlSize(.large)
				.disabled(isAdding || !canAdd)
			} else {
				Button {
					addContact()
				} label: {
					Label("Add Contact", systemImage: "person.crop.circle.badge.plus")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(isAdding || !canAdd)
			}
			Button("Cancel") { dismiss() }
				.controlSize(.large)
				.padding(.bottom)
		}
		.padding()
		.frame(maxWidth: 350)
		.sheet(item: $replyShareItem, onDismiss: { dismiss() }) { item in
			ContactReplyActivityView(url: item.url)
		}
		.onAppear {
			hasShareableSnapshot = MeshShareStore.load() != nil
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
		let base64UrlString: String
		if claimsInPersonExchange && !confirmsInPersonExchange {
			// The user did not attest to the in-person exchange, so the claim is stripped
			// before the contact goes to the radio. Anyone can set that bit in a link.
			var stripped = pendingContact.contact
			stripped.manuallyVerified = false
			guard let data = try? stripped.serializedData() else {
				failureMessage = String(localized: "Couldn't add this contact. Check that your node is connected and try again.")
				return
			}
			base64UrlString = data.base64EncodedString()
		} else {
			base64UrlString = pendingContact.base64UrlString
		}
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
				String(localized: "Here's my Meshtastic contact — let's stay connected on the mesh."),
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
