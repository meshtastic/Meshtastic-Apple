import Combine
import CoreData
import OSLog
import SwiftUI

@MainActor
class Router: ObservableObject {

	@Published
	var navigationState: NavigationState = NavigationState(selectedTab: .connect)

	private var cancellables: Set<AnyCancellable> = []
	
	// Add logic to listen for state changes and update badge count, similar to the original AppState
	init() {
		$navigationState
			.sink { _ in
				// You can add logic here to react to navigation state changes if needed
			}
			.store(in: &cancellables)
	}

	func route(url: URL) {
		guard url.scheme == "meshtastic" else {
			Logger.services.error("🛣 [App] Received routing URL \(url, privacy: .public) with invalid scheme. Ignoring route.")
			return
		}
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			Logger.services.error("🛣 [App] Received routing URL \(url, privacy: .public) with invalid host path. Ignoring route.")
			return
		}

		if components.path == "/messages" {
			routeMessages(components)
		} else if components.path == "/connect" {
			navigationState.selectedTab = .connect
		} else if components.path == "/nodes" {
			routeNodes(components)
		} else if components.path == "/map" {
			routeMap(components)
		} else if components.path.hasPrefix("/settings") {
			routeSettings(components)
		} else {
			Logger.services.warning("🛣 [App] Failed to route url: \(url, privacy: .public)")
		}
	}

	// MARK: Routing Helpers

	private func routeMessages(
		_ components: URLComponents
	) {
		let channelId = components.queryItems?
			.first(where: { $0.name == "channelId" })?
			.value
			.flatMap(Int32.init)
		let userNum = components.queryItems?
			.first(where: { $0.name == "userNum" })?
			.value
			.flatMap(Int64.init)
		let messageId = components.queryItems?
			.first(where: { $0.name == "messageId" })?
			.value
			.flatMap(Int64.init)

		let state: MessagesNavigationState? = if let channelId {
			.channels(channelId: channelId, messageId: messageId)
		} else if let userNum {
			.directMessages(userNum: userNum, messageId: messageId)
		} else {
			nil
		}
		navigationState.selectedTab = .messages
		navigationState.messages = state
	}

	private func routeNodes(_ components: URLComponents) {
		let nodeId = components.queryItems?
			.first(where: { $0.name == "nodenum" })?
			.value
			.flatMap(Int64.init)

		navigationState.selectedTab = .nodes
		navigationState.nodeListSelectedNodeNum = nodeId
	}

	private func routeMap(_ components: URLComponents) {
		let nodeId = components.queryItems?
			.first(where: { $0.name == "nodenum" })?
			.value
			.flatMap(Int64.init)
		let waypointId = components.queryItems?
			.first(where: { $0.name == "waypointId" })?
			.value
			.flatMap(Int64.init)

		navigationState.selectedTab = .map
		navigationState.map = if let nodeId {
			.selectedNode(nodeId)
		} else if let waypointId {
			.waypoint(waypointId)
		} else {
			nil
		}
	}

	private func routeSettings(_ components: URLComponents) {
		let settingFromPath = components.path
			.split(separator: "/")
			.dropFirst()
			.first
			.flatMap(String.init)
			.flatMap(SettingsNavigationState.init(rawValue:))

		navigationState.selectedTab = .settings
		navigationState.settings = settingFromPath
	}
}
