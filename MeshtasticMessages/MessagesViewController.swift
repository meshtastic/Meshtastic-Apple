//
//  MessagesViewController.swift
//  MeshtasticMessages
//

import Messages
import SwiftUI

final class MessagesViewController: MSMessagesAppViewController {
	private var viewModel: MessagesViewModel?

	override func viewDidLoad() {
		super.viewDidLoad()
		let model = MessagesViewModel(
			sendContact: { [weak self] in self?.insertContact() },
			sendChannels: { [weak self] indexes, mode in
				self?.insertChannels(indexes: indexes, mode: mode)
			},
			sendSticker: { [weak self] name, description in
				self?.insertSticker(named: name, description: description)
			},
			openInApp: { [weak self] url in self?.openInContainerApp(url) },
			addAndReply: { [weak self] url in self?.addContactAndReply(url) }
		)
		viewModel = model

		let host = UIHostingController(rootView: MessagesRootView(viewModel: model))
		addChild(host)
		host.view.translatesAutoresizingMaskIntoConstraints = false
		host.view.backgroundColor = .clear
		view.addSubview(host.view)
		NSLayoutConstraint.activate([
			host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			host.view.topAnchor.constraint(equalTo: view.topAnchor),
			host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
		host.didMove(toParent: self)
	}

	override func willBecomeActive(with conversation: MSConversation) {
		super.willBecomeActive(with: conversation)
		viewModel?.reload()
		inspectSelectedMessage(in: conversation)
	}

	override func didSelect(_ message: MSMessage, conversation: MSConversation) {
		super.didSelect(message, conversation: conversation)
		inspectSelectedMessage(in: conversation)
		requestPresentationStyle(.expanded)
	}

	private func inspectSelectedMessage(in conversation: MSConversation) {
		guard let url = conversation.selectedMessage?.url else {
			viewModel?.selectedPayload = nil
			return
		}
		if let contact = try? MeshContactURL.parse(url.absoluteString) {
			viewModel?.selectedPayload = .contact(url, exchangeRequested: contact.exchangeRequested)
		} else if (try? MeshtasticChannelURL.parse(url.absoluteString)) != nil {
			viewModel?.selectedPayload = .channels(url)
		} else {
			viewModel?.selectedPayload = nil
		}
	}

	private func insertContact() {
		guard let conversation = activeConversation,
			  let snapshot = viewModel?.snapshot,
			  let url = URL(string: snapshot.contactURL) else {
			viewModel?.errorMessage = "Open Meshtastic once after connecting to a radio."
			return
		}
		let message = card(
			url: url,
			caption: "Swap Meshtastic contacts",
			subcaption: snapshot.radioLongName,
			trailingCaption: snapshot.radioShortName,
			imageName: "chirpy"
		)
		conversation.insert(message) { [weak self] error in
			self?.show(error)
		}
	}

	private func insertChannels(indexes: Set<Int32>, mode: MeshChannelImportMode) {
		guard let conversation = activeConversation,
			  let snapshot = viewModel?.snapshot else {
			viewModel?.errorMessage = "Open Meshtastic once after connecting to a radio."
			return
		}
		do {
			let value = try MeshChannelSelection(snapshot: snapshot)
				.url(selectedIndexes: indexes, mode: mode)
			let selectedCount = snapshot.channels.count { indexes.contains($0.index) }
			guard let url = URL(string: value) else {
				throw MeshChannelSelection.SelectionError.invalidChannel
			}
			let message = card(
				url: url,
				caption: mode == .replace ? "Replace with my channels" : "Add my channels",
				subcaption: "\(selectedCount) selected from \(snapshot.radioLongName)",
				trailingCaption: snapshot.radioShortName,
				imageName: "mesh-logo"
			)
			conversation.insert(message) { [weak self] error in
				self?.show(error)
			}
		} catch {
			show(error)
		}
	}

	private func addContactAndReply(_ incomingURL: URL) {
		guard let conversation = activeConversation,
			  let snapshot = viewModel?.snapshot,
			  let replyURL = URL(string: snapshot.contactReplyURL) else {
			viewModel?.errorMessage = "Connect in Meshtastic once before exchanging contacts."
			return
		}
		let reply = card(
			url: replyURL,
			caption: "Here's mine!",
			subcaption: snapshot.radioLongName,
			trailingCaption: snapshot.radioShortName,
			imageName: "chirpy"
		)
		conversation.insert(reply) { [weak self] error in
			if let error {
				self?.show(error)
			} else {
				self?.openInContainerApp(MeshContactURL.withoutExchangeRequest(incomingURL))
			}
		}
	}

	private func openInContainerApp(_ url: URL) {
		let destination = containerAppURL(for: url)
		extensionContext?.open(destination) { [weak self] success in
			if !success {
				Task { @MainActor [weak self] in
					self?.viewModel?.errorMessage = "Open the Meshtastic app to import this share."
				}
			}
		}
	}

	private func containerAppURL(for sharedURL: URL) -> URL {
		guard let segment = sharedURL.pathComponents
			.filter({ $0 != "/" })
			.first else {
			return sharedURL
		}
		var value = "meshtastic:///\(segment)"
		if let query = sharedURL.query, !query.isEmpty {
			value += "?\(query)"
		}
		if let fragment = sharedURL.fragment, !fragment.isEmpty {
			value += "#\(fragment)"
		}
		return URL(string: value) ?? sharedURL
	}

	private func insertSticker(named name: String, description: String) {
		guard let conversation = activeConversation,
			  let fileURL = Bundle.main.url(forResource: name, withExtension: "png") else {
			viewModel?.errorMessage = "That sticker is missing from this build."
			return
		}
		do {
			let sticker = try MSSticker(contentsOfFileURL: fileURL, localizedDescription: description)
			conversation.insert(sticker) { [weak self] error in
				self?.show(error)
			}
		} catch {
			show(error)
		}
	}

	private func card(
		url: URL,
		caption: String,
		subcaption: String,
		trailingCaption: String,
		imageName: String
	) -> MSMessage {
		let layout = MSMessageTemplateLayout()
		layout.caption = caption
		layout.subcaption = subcaption
		layout.trailingCaption = trailingCaption
		if let imageURL = Bundle.main.url(forResource: imageName, withExtension: "png"),
		   let data = try? Data(contentsOf: imageURL) {
			layout.image = UIImage(data: data)
		}
		let message = MSMessage()
		message.url = url
		message.layout = layout
		message.summaryText = caption
		return message
	}

	private func show(_ error: Error?) {
		if let error {
			viewModel?.errorMessage = error.localizedDescription
		}
	}
}
