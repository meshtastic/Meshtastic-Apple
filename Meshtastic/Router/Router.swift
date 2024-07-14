import Combine
import CoreData
import OSLog
import SwiftUI

@MainActor
class Router: ObservableObject {

	@Published
	var navigationState: NavigationState

	private var cancellables: Set<AnyCancellable> = []

	init(
		navigationState: NavigationState = .bluetooth
	) {
		self.navigationState = navigationState

		$navigationState.sink { destination in
			Logger.services.info("Routed to \(String(describing: destination))")
		}.store(in: &cancellables)
	}

	func route(to destination: NavigationState) {
		navigationState = destination
	}

	func route(url: URL) {
		guard url.scheme == "meshtastic" else {
			Logger.services.error("Received routing URL \(url) with invalid scheme. Ignoring route.")
			return
		}
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			Logger.services.error("Received routing URL \(url) with invalid host path. Ignoring route.")
			return
		}

		if components.path == "/messages" {
			routeMessages(components)
		} else if components.path == "/bluetooth" {
			route(to: .bluetooth)
		} else if components.path == "/nodes" {
			routeNodes(components)
		} else if components.path == "/map" {
			routeMap(components)
		} else if components.path.hasPrefix("/settings") {
			routeSettings(components)
		} else {
			Logger.services.warning("Failed to route url: \(url)")
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
		route(to: .messages(state))
	}

	private func routeNodes(_ components: URLComponents) {
		let nodeId = components.queryItems?
			.first(where: { $0.name == "nodenum" })?
			.value
			.flatMap(Int64.init)
		route(to: .nodes(selectedNodeNum: nodeId))
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
		if let nodeId {
			route(to: .map(.selectedNode(nodeId)))
		} else if let waypointId {
			route(to: .map(.waypoint(waypointId)))
		} else {
			route(to: .map())
		}
	}

	private func routeSettings(_ components: URLComponents) {
		let settingFromPath = components.path
			.split(separator: "/")
			.dropFirst()
			.first
			.flatMap(String.init)
			.flatMap(SettingsNavigationState.init(rawValue:))

		route(to: .settings(settingFromPath))
	}
}
