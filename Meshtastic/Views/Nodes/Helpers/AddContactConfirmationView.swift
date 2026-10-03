//
//  AddContactConfirmationView.swift
//  Meshtastic
//
//  SwiftUI confirmation sheet for importing a contact from a
//  meshtastic.org/v/# URL (QR code, shared link, or NFC tag).
//

import SwiftUI
import SwiftData
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
	@State private var confirmsKeyReplacement = false

	/// The node db row for the contact being imported, if we hold one. A query rather than a
	/// lookup in `onAppear` so the key warning is part of the sheet's first layout rather than
	/// something that appears a beat after it has already been sized and shown.
	@Query private var storedNodes: [NodeInfoEntity]

	init(pendingContact: PendingContact, accessoryManager: AccessoryManager) {
		self.pendingContact = pendingContact
		self.accessoryManager = accessoryManager
		let num = Int64(pendingContact.contact.nodeNum)
		_storedNodes = Query(filter: #Predicate<NodeInfoEntity> { $0.num == num })
	}

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

	/// Importing would re-point this contact at a different public key than the node holds.
	///
	/// The node db mirrors the radio's, so the key stored here is the one the import would
	/// replace. A node we have never heard from has no row and no key, which reads as
	/// establishing one rather than replacing it.
	private var replacesStoredKey: Bool {
		pendingContact.contact.comparedWithStoredKey(storedNodes.first?.user?.publicKey) == .replacesStoredKey
	}

	/// A key replacement is gated on the person saying they expected it, the same shape as the
	/// in-person attestation and for the same reason — the link cannot vouch for itself, and the
	/// radio applies an `add_contact` without asking.
	private var keyReplacementAcknowledged: Bool {
		!replacesStoredKey || confirmsKeyReplacement
	}

	/// Everything that has to be true before the contact may go to the radio.
	private var canSubmit: Bool {
		canAdd && keyReplacementAcknowledged
	}

	var body: some View {
		// The sheet opens at the medium detent, which is shorter than this content once a
		// warning block is showing. Without the scroll view the buttons below the warning are
		// cut off, leaving no way to act on what the sheet is asking. `basedOnSize` keeps the
		// shorter states from bouncing like a scrollable list.
		ScrollView {
			content
		}
		.scrollBounceBehavior(.basedOnSize)
		.sheet(item: $replyShareItem, onDismiss: { dismiss() }) { item in
			ContactReplyActivityView(url: item.url)
		}
		.onAppear {
			hasShareableSnapshot = MeshShareStore.load() != nil
		}
	}

	private var content: some View {
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
			if replacesStoredKey && canAdd {
				VStack(alignment: .leading, spacing: 8) {
					Label {
						Text("This replaces a key you already have")
							.font(.footnote.weight(.medium))
					} icon: {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
					}
					Text("Your node already holds a different public key for this contact. Adding it replaces that key, and your messages to them will be encrypted to the new one. Continue only if you expected it to change — they reset their node or set it up again.")
						.font(.caption2)
						.foregroundColor(.secondary)
						.fixedSize(horizontal: false, vertical: true)
					Toggle(isOn: $confirmsKeyReplacement) {
						Text("Replace the stored key")
							.font(.footnote.weight(.medium))
					}
					.tint(.orange)
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
				.disabled(isAdding || !canSubmit || !hasShareableSnapshot)
				Button {
					addContact()
				} label: {
					Label("Just Add Contact", systemImage: "person.crop.circle.badge.plus")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
				.controlSize(.large)
				.disabled(isAdding || !canSubmit)
			} else {
				Button {
					addContact()
				} label: {
					Label("Add Contact", systemImage: "person.crop.circle.badge.plus")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(isAdding || !canSubmit)
			}
			Button("Cancel") { dismiss() }
				.controlSize(.large)
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
				// The radio takes the new key from the add_contact regardless; passing the
				// confirmation keeps the app's copy in step instead of flagging a mismatch for
				// a replacement the person just approved.
				try await accessoryManager.addContactFromURL(
					base64UrlString: base64UrlString,
					acceptsKeyReplacement: replacesStoredKey && confirmsKeyReplacement)
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

extension View {
	func contactImportSheet(
		_ pendingContact: Binding<PendingContact?>,
		accessoryManager: AccessoryManager
	) -> some View {
		sheet(item: pendingContact) { pendingContact in
			AddContactConfirmationView(
				pendingContact: pendingContact,
				accessoryManager: accessoryManager
			)
			.trackScreen(.addContact)
			.presentationDetents([.medium, .large])
			#if !targetEnvironment(macCatalyst)
			.presentationDragIndicator(.visible)
			#endif
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
			pendingContact: PendingContact(
				contact: contact,
				base64UrlString: "",
				exchangeRequested: true
			),
			accessoryManager: AccessoryManager.shared
		)
		// The sheet reads the node db to see whether the import would replace a stored key,
		// so the preview needs a container the way the app's scene provides one.
		.modelContainer(PersistenceController.preview.container)
	}
}
#endif
