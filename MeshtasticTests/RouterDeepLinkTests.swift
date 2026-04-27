import Foundation
import Testing

@testable import Meshtastic

// MARK: - Router Deep Link Routing

@Suite("Router URL Routing")
struct RouterURLRoutingTests {

	@Test @MainActor func route_messages_channelId() {
		let router = Router()
		let url = URL(string: "meshtastic:///messages?channelId=5")!
		router.route(url: url)
		#expect(router.selectedTab == .messages)
		if case .channels(let channelId, _) = router.messagesState {
			#expect(channelId == 5)
		} else {
			#expect(Bool(false), "Expected channels state")
		}
	}

	@Test @MainActor func route_messages_userNum() {
		let router = Router()
		let url = URL(string: "meshtastic:///messages?userNum=42")!
		router.route(url: url)
		#expect(router.selectedTab == .messages)
		if case .directMessages(let userNum, _) = router.messagesState {
			#expect(userNum == 42)
		} else {
			#expect(Bool(false), "Expected directMessages state")
		}
	}

	@Test @MainActor func route_messages_channelWithMessageId() {
		let router = Router()
		let url = URL(string: "meshtastic:///messages?channelId=3&messageId=100")!
		router.route(url: url)
		if case .channels(let ch, let msg) = router.messagesState {
			#expect(ch == 3)
			#expect(msg == 100)
		} else {
			#expect(Bool(false), "Expected channels state with messageId")
		}
	}

	@Test @MainActor func route_messages_noParams() {
		let router = Router()
		let url = URL(string: "meshtastic:///messages")!
		router.route(url: url)
		#expect(router.selectedTab == .messages)
		#expect(router.messagesState == nil)
	}

	@Test @MainActor func route_connect() {
		let router = Router()
		let url = URL(string: "meshtastic:///connect")!
		router.route(url: url)
		#expect(router.selectedTab == .connect)
	}

	@Test @MainActor func route_nodes_withNodeNum() {
		let router = Router()
		let url = URL(string: "meshtastic:///nodes?nodenum=12345")!
		router.route(url: url)
		#expect(router.selectedTab == .nodes)
		#expect(router.nodeListSelectedNodeNum == 12345)
	}

	@Test @MainActor func route_nodes_noParams() {
		let router = Router()
		let url = URL(string: "meshtastic:///nodes")!
		router.route(url: url)
		#expect(router.selectedTab == .nodes)
		#expect(router.nodeListSelectedNodeNum == nil)
	}

	@Test @MainActor func route_map_nodeNum() {
		let router = Router()
		let url = URL(string: "meshtastic:///map?nodenum=999")!
		router.route(url: url)
		#expect(router.selectedTab == .map)
		if case .selectedNode(let id) = router.mapState {
			#expect(id == 999)
		} else {
			#expect(Bool(false), "Expected selectedNode state")
		}
	}

	@Test @MainActor func route_map_waypointId() {
		let router = Router()
		let url = URL(string: "meshtastic:///map?waypointId=555")!
		router.route(url: url)
		#expect(router.selectedTab == .map)
		if case .waypoint(let id) = router.mapState {
			#expect(id == 555)
		} else {
			#expect(Bool(false), "Expected waypoint state")
		}
	}

	@Test @MainActor func route_map_noParams() {
		let router = Router()
		let url = URL(string: "meshtastic:///map")!
		router.route(url: url)
		#expect(router.selectedTab == .map)
		#expect(router.mapState == nil)
	}

	@Test @MainActor func route_settings_about() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/about")!
		router.route(url: url)
		#expect(router.selectedTab == .settings)
		#expect(router.settingsState == .about)
	}

	@Test @MainActor func route_settings_lora() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/lora")!
		router.route(url: url)
		#expect(router.selectedTab == .settings)
		#expect(router.settingsState == .lora)
	}

	@Test @MainActor func route_settings_mqtt() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/mqtt")!
		router.route(url: url)
		#expect(router.settingsState == .mqtt)
	}

	@Test @MainActor func route_settings_channels() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/channels")!
		router.route(url: url)
		#expect(router.settingsState == .channels)
	}

	@Test @MainActor func route_settings_user() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/user")!
		router.route(url: url)
		#expect(router.settingsState == .user)
	}

	@Test @MainActor func route_settings_bluetooth() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/bluetooth")!
		router.route(url: url)
		#expect(router.settingsState == .bluetooth)
	}

	@Test @MainActor func route_settings_device() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/device")!
		router.route(url: url)
		#expect(router.settingsState == .device)
	}

	@Test @MainActor func route_settings_display() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/display")!
		router.route(url: url)
		#expect(router.settingsState == .display)
	}

	@Test @MainActor func route_settings_network() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/network")!
		router.route(url: url)
		#expect(router.settingsState == .network)
	}

	@Test @MainActor func route_settings_position() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/position")!
		router.route(url: url)
		#expect(router.settingsState == .position)
	}

	@Test @MainActor func route_settings_power() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/power")!
		router.route(url: url)
		#expect(router.settingsState == .power)
	}

	@Test @MainActor func route_settings_security() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/security")!
		router.route(url: url)
		#expect(router.settingsState == .security)
	}

	@Test @MainActor func route_settings_serial() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/serial")!
		router.route(url: url)
		#expect(router.settingsState == .serial)
	}

	@Test @MainActor func route_settings_telemetry() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/telemetry")!
		router.route(url: url)
		#expect(router.settingsState == .telemetry)
	}

	@Test @MainActor func route_settings_tak() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/tak")!
		router.route(url: url)
		#expect(router.settingsState == .tak)
	}

	@Test @MainActor func route_settings_firmwareUpdates() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/firmwareUpdates")!
		router.route(url: url)
		#expect(router.settingsState == .firmwareUpdates)
	}

	@Test @MainActor func route_invalidScheme_ignored() {
		let router = Router()
		let url = URL(string: "https:///settings/about")!
		router.route(url: url)
		#expect(router.selectedTab == .connect) // Default, unchanged
	}

	@Test @MainActor func route_unknownPath_ignored() {
		let router = Router()
		let url = URL(string: "meshtastic:///unknown")!
		router.route(url: url)
		#expect(router.selectedTab == .connect) // Default, unchanged
	}

	@Test @MainActor func navigationState_computed() {
		let router = Router()
		router.selectedTab = .messages
		router.messagesState = .channels(channelId: 1)
		router.nodeListSelectedNodeNum = 42
		let state = router.navigationState
		#expect(state.selectedTab == .messages)
		#expect(state.nodeListSelectedNodeNum == 42)
	}

	@Test @MainActor func navigateToNodeDetail() {
		let router = Router()
		router.navigateToNodeDetail(nodeNum: 777)
		#expect(router.selectedTab == .nodes)
		#expect(router.nodeListSelectedNodeNum == 777)
	}
}
