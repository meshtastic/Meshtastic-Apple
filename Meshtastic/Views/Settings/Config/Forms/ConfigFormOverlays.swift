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
		AudioConfig.overlay(),
		BluetoothConfig.overlay(),
		CannedMessagesConfig.overlay(),
		DetectionSensorConfig.overlay(),
		DeviceConfig.overlay(),
		DisplayConfig.overlay(),
		ExternalNotificationConfig.overlay(),
		LoRaConfig.overlay(),
		MQTTConfig.overlay(),
		NetworkConfig.overlay(),
		NeighborInfoConfig.overlay(),
		PaxCounterConfig.overlay(),
		PositionConfig.overlay(),
		PowerConfig.overlay(),
		RangeTestConfig.overlay(),
		SecurityConfig.overlay(),
		SerialConfig.overlay(),
		StoreForwardConfig.overlay(),
		TAKModuleConfig.overlay(),
		TelemetryConfig.overlay(),
		TrafficManagementConfig.overlay()
	]

	/// Messages whose screens stay hand-written, and why.
	static let bespoke: [String: String] = [
		"meshtastic.ModuleConfig.MeshBeaconConfig": "a repeated broadcast_targets editor and channel resolution",
		"meshtastic.ModuleConfig.MapReportSettings": "not a screen: nested in MQTTConfig and laid out there through its flattened fields"
	]
}
