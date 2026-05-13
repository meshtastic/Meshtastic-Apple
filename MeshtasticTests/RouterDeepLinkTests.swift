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
		#expect(router.navigationState.nodeListSelectedNodeNum == 12345)
	}

	@Test @MainActor func route_nodes_noParams() {
		let router = Router()
		let url = URL(string: "meshtastic:///nodes")!
		router.route(url: url)
		#expect(router.selectedTab == .nodes)
		#expect(router.navigationState.nodeListSelectedNodeNum == nil)
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
		#expect(router.settingsPath.last == .about)
	}

	@Test @MainActor func route_settings_lora() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/lora")!
		router.route(url: url)
		#expect(router.selectedTab == .settings)
		#expect(router.settingsPath.last == .lora)
	}

	@Test @MainActor func route_settings_mqtt() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/mqtt")!
		router.route(url: url)
		#expect(router.settingsPath.last == .mqtt)
	}

	@Test @MainActor func route_settings_channels() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/channels")!
		router.route(url: url)
		#expect(router.settingsPath.last == .channels)
	}

	@Test @MainActor func route_settings_user() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/user")!
		router.route(url: url)
		#expect(router.settingsPath.last == .user)
	}

	@Test @MainActor func route_settings_bluetooth() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/bluetooth")!
		router.route(url: url)
		#expect(router.settingsPath.last == .bluetooth)
	}

	@Test @MainActor func route_settings_device() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/device")!
		router.route(url: url)
		#expect(router.settingsPath.last == .device)
	}

	@Test @MainActor func route_settings_display() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/display")!
		router.route(url: url)
		#expect(router.settingsPath.last == .display)
	}

	@Test @MainActor func route_settings_network() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/network")!
		router.route(url: url)
		#expect(router.settingsPath.last == .network)
	}

	@Test @MainActor func route_settings_position() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/position")!
		router.route(url: url)
		#expect(router.settingsPath.last == .position)
	}

	@Test @MainActor func route_settings_power() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/power")!
		router.route(url: url)
		#expect(router.settingsPath.last == .power)
	}

	@Test @MainActor func route_settings_security() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/security")!
		router.route(url: url)
		#expect(router.settingsPath.last == .security)
	}

	@Test @MainActor func route_settings_serial() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/serial")!
		router.route(url: url)
		#expect(router.settingsPath.last == .serial)
	}

	@Test @MainActor func route_settings_telemetry() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/telemetry")!
		router.route(url: url)
		#expect(router.settingsPath.last == .telemetry)
	}

	@Test @MainActor func route_settings_tak() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/tak")!
		router.route(url: url)
		#expect(router.settingsPath.last == .tak)
	}

	@Test @MainActor func route_settings_firmwareUpdates() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/firmwareUpdates")!
		router.route(url: url)
		#expect(router.settingsPath.last == .firmwareUpdates)
	}

	// MARK: - Missing Settings Deep Links

	@Test @MainActor func route_settings_appSettings() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/appSettings")!
		router.route(url: url)
		#expect(router.selectedTab == .settings)
		#expect(router.settingsPath.last == .appSettings)
	}

	@Test @MainActor func route_settings_routes() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/routes")!
		router.route(url: url)
		#expect(router.settingsPath.last == .routes)
	}

	@Test @MainActor func route_settings_routeRecorder() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/routeRecorder")!
		router.route(url: url)
		#expect(router.settingsPath.last == .routeRecorder)
	}

	@Test @MainActor func route_settings_shareQRCode() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/shareQRCode")!
		router.route(url: url)
		#expect(router.settingsPath.last == .shareQRCode)
	}

	@Test @MainActor func route_settings_ambientLighting() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/ambientLighting")!
		router.route(url: url)
		#expect(router.settingsPath.last == .ambientLighting)
	}

	@Test @MainActor func route_settings_cannedMessages() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/cannedMessages")!
		router.route(url: url)
		#expect(router.settingsPath.last == .cannedMessages)
	}

	@Test @MainActor func route_settings_detectionSensor() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/detectionSensor")!
		router.route(url: url)
		#expect(router.settingsPath.last == .detectionSensor)
	}

	@Test @MainActor func route_settings_externalNotification() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/externalNotification")!
		router.route(url: url)
		#expect(router.settingsPath.last == .externalNotification)
	}

	@Test @MainActor func route_settings_paxCounter() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/paxCounter")!
		router.route(url: url)
		#expect(router.settingsPath.last == .paxCounter)
	}

	@Test @MainActor func route_settings_rangeTest() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/rangeTest")!
		router.route(url: url)
		#expect(router.settingsPath.last == .rangeTest)
	}

	@Test @MainActor func route_settings_ringtone() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/ringtone")!
		router.route(url: url)
		#expect(router.settingsPath.last == .ringtone)
	}

	@Test @MainActor func route_settings_storeAndForward() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/storeAndForward")!
		router.route(url: url)
		#expect(router.settingsPath.last == .storeAndForward)
	}

	@Test @MainActor func route_settings_debugLogs() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/debugLogs")!
		router.route(url: url)
		#expect(router.settingsPath.last == .debugLogs)
	}

	@Test @MainActor func route_settings_appFiles() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/appFiles")!
		router.route(url: url)
		#expect(router.settingsPath.last == .appFiles)
	}

	@Test @MainActor func route_settings_tools() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/tools")!
		router.route(url: url)
		#expect(router.settingsPath.last == .tools)
	}

	@Test @MainActor func route_settings_coreDataBrowser() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/coreDataBrowser")!
		router.route(url: url)
		#expect(router.settingsPath.last == .coreDataBrowser)
	}

	@Test @MainActor func route_settings_helpDocs() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/helpDocs")!
		router.route(url: url)
		#expect(router.settingsPath.last == .helpDocs)
	}

	@Test @MainActor func route_settings_localMeshDiscovery() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/localMeshDiscovery")!
		router.route(url: url)
		#expect(router.selectedTab == .settings)
		#expect(router.settingsPath.last == .localMeshDiscovery)
	}

	@Test @MainActor func route_settings_localMeshDiscovery_history() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/localMeshDiscovery/history")!
		router.route(url: url)
		#expect(router.settingsPath.last == .localMeshDiscovery)
		#expect(router.discoveryShowHistory == true)
	}

	@Test @MainActor func route_settings_takConfig() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/takConfig")!
		router.route(url: url)
		#expect(router.settingsPath.last == .takConfig)
	}

	// MARK: - Navigation Path Tests

	@Test @MainActor func popToRoot_nodes() {
		let router = Router()
		router.navigateToNodeDetail(nodeNum: 123)
		#expect(router.selectedNodeNum == 123)
		router.popToRoot(tab: .nodes)
		#expect(router.selectedNodeNum == nil)
		#expect(router.selectedNodeNum == nil)
	}

	@Test @MainActor func popToRoot_settings() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings/lora")!
		router.route(url: url)
		#expect(router.settingsPath.count == 1)
		router.popToRoot(tab: .settings)
		#expect(router.settingsPath.isEmpty)
	}

	@Test @MainActor func navigateToNodeDetail_sameTab() {
		let router = Router()
		router.selectedTab = .nodes
		router.navigateToNodeDetail(nodeNum: 555)
		#expect(router.selectedNodeNum == 555)
		#expect(router.selectedNodeNum == 555)
	}

	@Test @MainActor func navigateToNodeDetail_crossTab() {
		let router = Router()
		router.selectedTab = .messages
		router.navigateToNodeDetail(nodeNum: 888)
		// Tab switches immediately, path deferred
		#expect(router.selectedTab == .nodes)
		#expect(router.selectedNodeNum == 888)
	}

	@Test @MainActor func route_settings_noParams() {
		let router = Router()
		let url = URL(string: "meshtastic:///settings")!
		router.route(url: url)
		#expect(router.selectedTab == .settings)
		#expect(router.settingsPath.isEmpty)
	}
}
