//
//  ConfigFormOverlays.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import Foundation

/// Every screen on the generic form, and every configuration message that is not.
///
/// `ConfigFormOverlayTests` validates each overlay in `all` and checks that every
/// message with a settings screen appears in one list or the other, so a screen can
/// neither be half-migrated nor forgotten.
enum ConfigFormOverlays {
	static let all: [any AnyConfigFormOverlay] = [
		AmbientLightingConfig.overlay(),
		BluetoothConfig.overlay(),
		DeviceConfig.overlay(),
		DisplayConfig.overlay(),
		ExternalNotificationConfig.overlay(),
		NeighborInfoConfig.overlay(),
		PaxCounterConfig.overlay(),
		RangeTestConfig.overlay(),
		SerialConfig.overlay(),
		StoreForwardConfig.overlay(),
		TelemetryConfig.overlay()
	]

	/// Messages whose screens stay hand-written, and why.
	static let bespoke: [String: String] = [
		"meshtastic.Config.LoRaConfig": "region, preset, bandwidth and coding rate constrain each other from live radio data",
		"meshtastic.Config.SecurityConfig": "key management, lockdown and a repeated admin_key field",
		"meshtastic.Config.NetworkConfig": "static IPv4 as dotted quads over a nested message, with validation",
		"meshtastic.ModuleConfig.MeshBeaconConfig": "a repeated broadcast_targets editor and channel resolution",
		"meshtastic.ModuleConfig.CannedMessageConfig": "the messages themselves travel in a separate admin message",
		// Not migrated yet. Each moves to `all` in its own pull request.
		"meshtastic.Config.PositionConfig": "pending",
		"meshtastic.Config.PowerConfig": "pending",
		"meshtastic.ModuleConfig.AudioConfig": "pending",
		"meshtastic.ModuleConfig.DetectionSensorConfig": "pending",
		"meshtastic.ModuleConfig.MQTTConfig": "pending",
		"meshtastic.ModuleConfig.MapReportSettings": "pending, with MQTT",
		"meshtastic.ModuleConfig.TAKConfig": "pending: Team and MemberRole values have no labels upstream yet, so its pickers would show case names",
		"meshtastic.ModuleConfig.TrafficManagementConfig": "pending"
	]
}
