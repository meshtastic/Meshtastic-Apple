// MARK: CarPlaySceneDelegate
//
//  CarPlaySceneDelegate.swift
//  Meshtastic
//
//  CarPlay Communication app scene delegate.
//  For communication apps, the system provides the messaging UI.
//  This delegate manages the CarPlay scene lifecycle and shows
//  favorite contacts and channels for quick messaging via Siri.
//

import CarPlay
import Combine
import CoreData
import Intents
import OSLog

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

	var interfaceController: CPInterfaceController?
	private var cancellables = Set<AnyCancellable>()
	private var context: NSManagedObjectContext {
		PersistenceController.shared.container.viewContext
	}

	// MARK: - CPTemplateApplicationSceneDelegate

	func templateApplicationScene(
		_ templateApplicationScene: CPTemplateApplicationScene,
		didConnect interfaceController: CPInterfaceController
	) {
		Logger.services.info("🚗 [CarPlay] Connected")
		self.interfaceController = interfaceController

		let rootTemplate = buildRootTemplate()
		interfaceController.setRootTemplate(rootTemplate, animated: false, completion: nil)

		// Observe connection state changes and refresh the template
		AccessoryManager.shared.$isConnected
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				self?.refreshRootTemplate()
			}
			.store(in: &cancellables)
	}

	func templateApplicationScene(
		_ templateApplicationScene: CPTemplateApplicationScene,
		didDisconnectInterfaceController interfaceController: CPInterfaceController
	) {
		Logger.services.info("🚗 [CarPlay] Disconnected")
		cancellables.removeAll()
		self.interfaceController = nil
	}

	// MARK: - Root Template

	private func refreshRootTemplate() {
		guard let interfaceController else { return }
		let rootTemplate = buildRootTemplate()
		interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
	}

	private func buildRootTemplate() -> CPTemplate {
		let connected = AccessoryManager.shared.isConnected

		var sections = [CPListSection]()

		// Status section
		let statusItem = CPListItem(
			text: connected ? "Connected" : "Not Connected",
			detailText: connected
				? (AccessoryManager.shared.activeConnection?.device.name ?? "Unknown Device")
				: "Open Meshtastic on your phone to connect",
			image: UIImage(systemName: connected
				? "antenna.radiowaves.left.and.right"
				: "antenna.radiowaves.left.and.right.slash")
		)
		statusItem.isEnabled = false
		sections.append(CPListSection(items: [statusItem], header: "Status", sectionIndexTitle: nil))

		if connected {
			// Favorite contacts section
			let favoriteItems = fetchFavoriteContactItems()
			if !favoriteItems.isEmpty {
				sections.append(CPListSection(items: favoriteItems, header: "Favorites", sectionIndexTitle: nil))
			}

			// Channels section
			let channelItems = fetchChannelItems()
			if !channelItems.isEmpty {
				sections.append(CPListSection(items: channelItems, header: "Channels", sectionIndexTitle: nil))
			}
		}

		let listTemplate = CPListTemplate(title: "Meshtastic", sections: sections)
		listTemplate.tabImage = UIImage(systemName: "antenna.radiowaves.left.and.right")
		return listTemplate
	}

	// MARK: - Data Fetching

	private func fetchFavoriteContactItems() -> [CPListItem] {
		let request: NSFetchRequest<NodeInfoEntity> = NodeInfoEntity.fetchRequest()
		request.predicate = NSPredicate(format: "favorite == YES AND num != %lld", AccessoryManager.shared.activeDeviceNum ?? 0)
		request.sortDescriptors = [
			NSSortDescriptor(key: "user.longName", ascending: true)
		]
		request.relationshipKeyPathsForPrefetching = ["user"]

		do {
			let nodes = try context.fetch(request)
			return nodes.compactMap { node -> CPListItem? in
				guard let user = node.user else { return nil }
				let name = user.longName ?? user.shortName ?? "Unknown"
				let shortName = user.shortName ?? "?"
				let item = CPListItem(
					text: name,
					detailText: shortName,
					image: UIImage(systemName: "person.circle.fill")
				)
				item.handler = { [weak self] _, completion in
					self?.startMessageIntent(toNodeNum: node.num, name: name)
					completion()
				}
				item.isEnabled = true
				return item
			}
		} catch {
			Logger.services.error("🚗 [CarPlay] Failed to fetch favorites: \(error.localizedDescription, privacy: .public)")
			return []
		}
	}

	private func fetchChannelItems() -> [CPListItem] {
		guard let connectedNum = AccessoryManager.shared.activeDeviceNum,
			  let connectedNode = getNodeInfo(id: connectedNum, context: context),
			  let myInfo = connectedNode.myInfo,
			  let channels = myInfo.channels?.array as? [ChannelEntity] else {
			return []
		}

		return channels.compactMap { channel -> CPListItem? in
			guard channel.role > 0 else { return nil }
			let name = (channel.name?.isEmpty ?? true)
				? (channel.index == 0 ? "Primary Channel" : "Channel \(channel.index)")
				: channel.name!
			let item = CPListItem(
				text: name,
				detailText: channel.index == 0 ? "Primary" : "Ch \(channel.index)",
				image: UIImage(systemName: channel.index == 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
			)
			item.handler = { [weak self] _, completion in
				self?.startChannelMessageIntent(channelIndex: Int(channel.index), channelName: name)
				completion()
			}
			item.isEnabled = true
			return item
		}
	}

	// MARK: - Siri Message Intents

	private func startMessageIntent(toNodeNum: Int64, name: String) {
		let person = INPerson(
			personHandle: INPersonHandle(value: "\(toNodeNum)", type: .unknown),
			nameComponents: nil,
			displayName: name,
			image: nil,
			contactIdentifier: nil,
			customIdentifier: "meshtastic-node-\(toNodeNum)"
		)
		let intent = INSendMessageIntent(
			recipients: [person],
			outgoingMessageType: .outgoingMessageText,
			content: nil,
			speakableGroupName: nil,
			conversationIdentifier: "dm-\(toNodeNum)",
			serviceName: "Meshtastic",
			sender: nil,
			attachments: nil
		)
		let interaction = INInteraction(intent: intent, response: nil)
		interaction.direction = .outgoing
		interaction.donate { error in
			if let error {
				Logger.services.error("🚗 [CarPlay] DM intent donation error: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	private func startChannelMessageIntent(channelIndex: Int, channelName: String) {
		let groupName = INSpeakableString(spokenPhrase: channelName)
		let intent = INSendMessageIntent(
			recipients: nil,
			outgoingMessageType: .outgoingMessageText,
			content: nil,
			speakableGroupName: groupName,
			conversationIdentifier: "channel-\(channelIndex)",
			serviceName: "Meshtastic",
			sender: nil,
			attachments: nil
		)
		let interaction = INInteraction(intent: intent, response: nil)
		interaction.direction = .outgoing
		interaction.donate { error in
			if let error {
				Logger.services.error("🚗 [CarPlay] Channel intent donation error: \(error.localizedDescription, privacy: .public)")
			}
		}
	}
}
