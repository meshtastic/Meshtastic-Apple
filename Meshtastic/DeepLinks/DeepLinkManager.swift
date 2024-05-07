//
//  DeepLinkManager.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 5/5/24.
//

import Foundation

protocol DeepLinkTabManager {
	func handle(deepLink: String, selectedTab: inout Tab) -> Bool
}

@available(iOS 17.0, *)
@Observable
class DeepLinkManager {
	var selectedTab: Tab = .ble
	var features: [DeepLinkTabManager]

	init() {
		self.features = [
			DeepLinkManagerMessages(),
			DeepLinkManagerBluetooth(),
			DeepLinkManagerNodes(),
			DeepLinkManagerMap(),
			DeepLinkManagerSettings()
		]
	}

	func handleDeepLink(deepLink: String) {
		for handler in features {
			if handler.handle(deepLink: deepLink, selectedTab: &selectedTab) {
				return
			}
		}
	}
}

class DeepLinkManagerBluetooth: DeepLinkTabManager {
	func handle(deepLink: String, selectedTab: inout Tab) -> Bool {
		if deepLink.contains("bluetooth") {
			selectedTab = .ble
			return true
		}
		return false
	}
}

class DeepLinkManagerMessages: DeepLinkTabManager {
	
	var channel: String = ""
	var messageId: String = ""
	
	func handle(deepLink: String, selectedTab: inout Tab) -> Bool {
		if deepLink.contains("messages") {
			selectedTab = .messages
			extractData(from: deepLink)
			return true
		}

		return false
	}
	private func extractData(from deepLink: String) {
			let temp = deepLink.replacingOccurrences(of: "meshtastic://messages?", with: "")
			let params = temp.components(separatedBy: "&")
			guard params.count == 2 else { return }
			channel = params[0].replacingOccurrences(of: "channel=", with: "")
			messageId = params[1].replacingOccurrences(of: "messageId=", with: "")
	}
}

class DeepLinkManagerMap: DeepLinkTabManager {
	func handle(deepLink: String, selectedTab: inout Tab) -> Bool {
		if deepLink.contains("map") {
			selectedTab = .map
			return true
		}
		return false
	}
}

class DeepLinkManagerNodes: DeepLinkTabManager {
	func handle(deepLink: String, selectedTab: inout Tab) -> Bool {
		if deepLink.contains("nodes") {
			selectedTab = .nodes
			return true
		}
		return false
	}
}

class DeepLinkManagerSettings: DeepLinkTabManager {
	func handle(deepLink: String, selectedTab: inout Tab) -> Bool {
		if deepLink.contains("settings") {
			selectedTab = .settings
			return true
		}
		return false
	}
}
