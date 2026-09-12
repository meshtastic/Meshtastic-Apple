//
//  ScreenName.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/12/26.
//

import Foundation

/// Every screen name reported to RUM, in one list.
///
/// One list because two screens sharing a name silently merge their crashes and hangs into one
/// bucket. Swift rejects a duplicate raw value, so that collision is a build error instead.
///
/// The raw values are the grouping key for a screen's history in Error Tracking — changing one
/// splits that screen's past from its future, so treat them as fixed. They are deliberately not
/// localized: a name that followed the device language would scatter a screen across as many
/// buckets as there are languages.
enum ScreenName: String, CaseIterable {

	// MARK: Tabs

	case messages = "Messages"
	case nodes = "Nodes"
	case map = "Map"
	case settings = "Settings"
	case connect = "Connect"

	// MARK: Messages

	case channelMessages = "Channel Messages"
	case directMessages = "Direct Messages"
	case nodeDetail = "Node Detail"
	case channelsHelp = "Channels Help"
	case saveChannelQRCode = "Save Channel QR Code"
	case addContact = "Add Contact"

	// MARK: App root

	case lockdown = "Lockdown"

	// MARK: Settings

	case about = "About Meshtastic"
	case appSettings = "App Settings"
	case routes = "Routes"
	case routeRecorder = "Route Recorder"
	case lora = "LoRa Config"
	case channels = "Channel Config"
	case shareQRCode = "Share QR Code"
	case user = "User Config"
	case bluetooth = "Bluetooth Config"
	case device = "Device Config"
	case display = "Display Config"
	case network = "Network Config"
	case position = "Position Config"
	case power = "Power Config"
	case ambientLighting = "Ambient Lighting Config"
	case audio = "Audio Config"
	case cannedMessages = "Canned Messages Config"
	case detectionSensor = "Detection Sensor Config"
	case meshBeacon = "Mesh Beacon Config"
	case externalNotification = "External Notification Config"
	case mqtt = "MQTT Config"
	case neighborInfo = "Neighbor Info Config"
	case rangeTest = "Range Test Config"
	case paxCounter = "PAX Counter Config"
	case ringtone = "Ringtone Config"
	case serial = "Serial Config"
	case security = "Security Config"
	case storeAndForward = "Store and Forward Config"
	case telemetry = "Telemetry Config"
	case trafficManagement = "Traffic Management Config"
	case debugLogs = "Logs"
	case traceRoutes = "Trace Routes"
	case appFiles = "App Files"
	case firmwareUpdates = "Firmware Updates"
	case deviceLinks = "Device Links"
	case tak = "TAK Server"
	case takConfig = "TAK Module Config"
	case tools = "Tools"
	case coreDataBrowser = "Data Browser"
	case localMeshDiscovery = "Local Mesh Discovery"
	case helpDocs = "Help and Documentation"
	case backupManagement = "Backup Management"

	// MARK: Screens reached from Settings

	case appIconPicker = "App Icon Picker"
	case askChirpy = "Ask Chirpy"
	case channelEditor = "Channel Editor"
	case discoverySession = "Discovery Session"
	case importDeviceProfile = "Import Device Profile"
	case logDetail = "Log Detail"
	case mapDataFiles = "Map Data Files"
	case routeRecordingDetails = "Route Recording Details"

	// MARK: Data browser

	case dataBrowserEntities = "Data Browser Entities"
	case dataBrowserEntity = "Data Browser Entity"
	case dataBrowserRelationships = "Data Browser Relationships"

	// MARK: Firmware

	case nordicDFUUpdate = "Nordic DFU Update"
	case esp32Update = "ESP32 Update"
	case esp32WiFiUpdate = "ESP32 Wi-Fi Update"
	case esp32BLEUpdate = "ESP32 BLE Update"
	case firmwareSecurityWarning = "Firmware Security Warning"

	// MARK: Provisioning

	case wifiProvisioning = "Wi-Fi Provisioning"
	case wifiPassword = "Wi-Fi Password"
	case hiddenWiFiNetwork = "Hidden Wi-Fi Network"

	// MARK: Map

	case mapItemPicker = "Map Item Picker"
	case waypoint = "Waypoint"
	case mapLegend = "Map Legend"
	case coverageEstimate = "Coverage Estimate"
	case positionDetail = "Position Detail"

	// MARK: Node detail

	case powerChannelLabels = "Power Channel Labels"
	case noiseFloorInfo = "Noise Floor Info"

	// MARK: Onboarding

	case onboardingNotifications = "Onboarding Notifications"
	case onboardingLocation = "Onboarding Location"
	case onboardingBluetooth = "Onboarding Bluetooth"
	case onboardingLocalNetwork = "Onboarding Local Network"
	case onboardingSiri = "Onboarding Siri"
}
