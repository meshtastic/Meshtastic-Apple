//
//  MessagesViewModel.swift
//  MeshtasticMessages
//

import Foundation

@MainActor
final class MessagesViewModel: ObservableObject {
	enum SelectedPayload {
		case contact(URL, exchangeRequested: Bool)
		case channels(URL)
	}

	@Published var snapshot: MeshShareSnapshot?
	@Published var selectedPayload: SelectedPayload?
	@Published var errorMessage: String?

	let sendContact: () -> Void
	let sendChannels: (Set<Int32>, MeshChannelImportMode) -> Void
	let sendSticker: (String, String) -> Void
	let openInApp: (URL) -> Void
	let addAndReply: (URL) -> Void

	init(
		sendContact: @escaping () -> Void,
		sendChannels: @escaping (Set<Int32>, MeshChannelImportMode) -> Void,
		sendSticker: @escaping (String, String) -> Void,
		openInApp: @escaping (URL) -> Void,
		addAndReply: @escaping (URL) -> Void
	) {
		self.sendContact = sendContact
		self.sendChannels = sendChannels
		self.sendSticker = sendSticker
		self.openInApp = openInApp
		self.addAndReply = addAndReply
		reload()
	}

	func reload() {
		snapshot = MeshShareStore.load()
	}
}
