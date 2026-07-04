//
//  ConfigModels.swift
//  Meshtastic
//
//  SwiftData models for all device and module configuration entities.
//

import Foundation
import SwiftData

@Model
final class AmbientLightingConfigEntity {
	var blue: Int32 = 0
	var current: Int32 = 0
	var green: Int32 = 0
	var ledState: Bool = false
	var red: Int32 = 0
	var ambientLightingConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class AudioConfigEntity {
	var codec2Enabled: Bool = false
	var pttPin: Int32 = 0
	var bitrate: Int32 = 0
	var i2sWs: Int32 = 0
	var i2sSd: Int32 = 0
	var i2sDin: Int32 = 0
	var i2sSck: Int32 = 0
	var audioConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class BluetoothConfigEntity {
	var deviceLoggingEnabled: Bool = false
	var enabled: Bool = false
	var fixedPin: Int32 = 123456
	var mode: Int32 = 0
	var bluetoothConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class CannedMessageConfigEntity {
	var enabled: Bool = false
	var inputbrokerEventCcw: Int32 = 0
	var inputbrokerEventCw: Int32 = 0
	var inputbrokerEventPress: Int32 = 0
	var inputbrokerPinA: Int32 = 0
	var inputbrokerPinB: Int32 = 0
	var inputbrokerPinPress: Int32 = 0
	var messages: String?
	var rotary1Enabled: Bool = false
	var sendBell: Bool = false
	var updown1Enabled: Bool = false
	var cannedMessagesConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class DetectionSensorConfigEntity {
	var enabled: Bool = false
	var minimumBroadcastSecs: Int32 = 0
	var monitorPin: Int32 = 0
	var name: String?
	var sendBell: Bool = false
	var stateBroadcastSecs: Int32 = 0
	var triggerType: Int32 = 0
	var usePullup: Bool = false
	var detectionSensorConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class MeshBeaconConfigEntity {
	/// Bitwise-OR of `ModuleConfig.MeshBeaconConfig.Flags` (listen / broadcast / legacy-split).
	var flags: Int32 = 0
	/// Human-readable text broadcast in each beacon (firmware limit: 100 UTF-8 bytes).
	var broadcastMessage: String = ""
	/// Channel the beacon *advertises* to listeners (offer_channel). Empty name = no offer.
	var broadcastOfferChannelName: String = ""
	var broadcastOfferChannelPSK: Data = Data()
	/// RegionCodes raw value advertised in offer_region; 0 = unset / not offered.
	var broadcastOfferRegion: Int32 = 0
	/// ModemPresets raw value advertised in offer_preset, or -1 when not offered (0 = LongFast).
	var broadcastOfferPreset: Int32 = -1
	/// Single-target TX channel (broadcast_on_channel); used only when `broadcastTargets` is empty.
	var broadcastOnChannelName: String = ""
	var broadcastOnChannelPSK: Data = Data()
	/// RegionCodes raw value for single-target TX (broadcast_on_region); 0 = unset (running config).
	var broadcastOnRegion: Int32 = 0
	/// ModemPresets raw value for single-target TX, or -1 when unset (running config).
	var broadcastOnPreset: Int32 = -1
	/// How often to broadcast; firmware minimum & default is 3600 s.
	var broadcastIntervalSecs: Int32 = 3600
	/// Spoof the `from` of outgoing beacons as this node id; 0 = local node.
	var broadcastSendAsNode: Int64 = 0

	@Relationship(deleteRule: .cascade, inverse: \BroadcastTargetEntity.meshBeaconConfig)
	var broadcastTargets: [BroadcastTargetEntity] = []

	var meshBeaconConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class BroadcastTargetEntity {
	/// ModemPresets raw value for this target, or -1 when unset (falls back to running config).
	var preset: Int32 = -1
	/// RegionCodes raw value for this target; 0 = unset (running config).
	var region: Int32 = 0
	/// Index into the node's channel table to transmit this target on, or -1 when unset.
	var channelIndex: Int32 = -1

	var meshBeaconConfig: MeshBeaconConfigEntity?

	init() {}

	init(preset: Int32, region: Int32, channelIndex: Int32) {
		self.preset = preset
		self.region = region
		self.channelIndex = channelIndex
	}
}

@Model
final class DeviceConfigEntity {
	var buttonGpio: Int32 = 0
	var buzzerGpio: Int32 = 0
	var debugLogEnabled: Bool = false
	var disableTripleClick: Bool = false
	var doubleTapAsButtonPress: Bool = false
	var isManaged: Bool = false
	var ledHeartbeatEnabled: Bool = true
	var nodeInfoBroadcastSecs: Int32 = 0
	var rebroadcastMode: Int32 = 0
	var role: Int32 = 0
	var serialEnabled: Bool = false
	var tripleClickAsAdHocPing: Bool = true
	var tzdef: String?
	var deviceConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class DisplayConfigEntity {
	var compassNorthTop: Bool = false
	var compassOrientation: Int32 = 0
	var displayMode: Int32 = 0
	var flipScreen: Bool = false
	var headingBold: Bool = true
	var oledType: Int32 = 0
	var screenCarouselInterval: Int32 = 0
	var screenOnSeconds: Int32 = 0
	var units: Int32 = 0
	var use12HClock: Bool = false
	var wakeOnTapOrMotion: Bool = false
	var displayConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class ExternalNotificationConfigEntity {
	var active: Bool = false
	var alertBell: Bool = false
	var alertBellBuzzer: Bool = false
	var alertBellVibra: Bool = false
	var alertMessage: Bool = false
	var alertMessageBuzzer: Bool = false
	var alertMessageVibra: Bool = false
	var enabled: Bool = false
	var nagTimeout: Int32 = 0
	var output: Int32 = 0
	var outputBuzzer: Int32 = 0
	var outputMilliseconds: Int32 = 0
	var outputVibra: Int32 = 0
	var useI2SAsBuzzer: Bool = false
	var usePWM: Bool = true
	var externalNotificationConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class LoRaConfigEntity {
	var bandwidth: Int32 = 0
	var channelNum: Int32 = 0
	var codingRate: Int32 = 0
	var frequencyOffset: Float = 0
	var hopLimit: Int32 = 0
	var ignoreMqtt: Bool = false
	var modemPreset: Int32 = 0
	var okToMqtt: Bool = false
	var overrideDutyCycle: Bool = false
	var overrideFrequency: Float = 0.0
	var regionCode: Int32 = 0
	var spreadFactor: Int32 = 0
	var sx126xRxBoostedGain: Bool = false
	var txEnabled: Bool = true
	var txPower: Int32 = 0
	var usePreset: Bool = true
	var loRaConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class MQTTConfigEntity {
	var address: String?
	var enabled: Bool = false
	var encryptionEnabled: Bool = false
	var jsonEnabled: Bool = false
	var mapPositionPrecision: Int32 = 13
	var mapPublishIntervalSecs: Int32 = 0
	var mapReportingEnabled: Bool = false
	var mapReportingShouldReportLocation: Bool = false
	var password: String?
	var proxyToClientEnabled: Bool = false
	var root: String? = "msh"
	var tlsEnabled: Bool = false
	var username: String?
	var mqttConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class NetworkConfigEntity {
	var addressMode: Int32 = 0
	var dns: Int32 = 0
	var enabledProtocols: Int32 = 0
	var ethEnabled: Bool = false
	var gateway: Int32 = 0
	var ip: Int32 = 0
	var ntpServer: String?
	var rsyslogServer: String?
	var subnet: Int32 = 0
	var wifiEnabled: Bool = false
	var wifiMode: Int32 = 0
	var wifiPsk: String?
	var wifiSsid: String?
	var networkConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class NeighborInfoConfigEntity {
	var enabled: Bool = false
	var transmitOverLora: Bool = false
	var updateInterval: Int32 = 0
	var neighborInfoConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class PaxCounterConfigEntity {
	var bleThreshold: Int32 = 0
	var enabled: Bool = false
	var updateInterval: Int32 = 0
	var wifiThreshold: Int32 = -80
	var paxCounterConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class PositionConfigEntity {
	var broadcastSmartMinimumDistance: Int32 = 0
	var broadcastSmartMinimumIntervalSecs: Int32 = 0
	var deviceGpsEnabled: Bool = false
	var fixedPosition: Bool = false
	var gpsAttemptTime: Int32 = 0
	var gpsEnGpio: Int32 = 0
	var gpsMode: Int32 = 0
	var gpsUpdateInterval: Int32 = 0
	var positionBroadcastSeconds: Int32 = 0
	var positionFlags: Int32 = 0
	var rxGpio: Int32 = 0
	var smartPositionEnabled: Bool = false
	var txGpio: Int32 = 0
	var positionConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class PowerConfigEntity {
	var adcMultiplierOverride: Float = 0
	var deviceBatteryInaAddress: Int32 = 0
	var isPowerSaving: Bool = false
	var lsSecs: Int32 = 0
	var minWakeSecs: Int32 = 0
	var onBatteryShutdownAfterSecs: Int32 = 0
	var waitBluetoothSecs: Int32 = 0
	var powerConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class RangeTestConfigEntity {
	var enabled: Bool = false
	var save: Bool = false
	var sender: Int32 = 0
	var rangeTestConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class RTTTLConfigEntity {
	var ringtone: String?
	var rtttlConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class SecurityConfigEntity {
	var adminChannelEnabled: Bool = false
	var adminKey: Data?
	var adminKey2: Data?
	var adminKey3: Data?
	var bluetoothLoggingEnabled: Bool = false
	var debugLogApiEnabled: Bool = false
	var isManaged: Bool = false
	var privateKey: Data?
	var publicKey: Data?
	var serialEnabled: Bool = false
	var securityConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class SerialConfigEntity {
	var baudRate: Int32 = 0
	var echo: Bool = false
	var enabled: Bool = false
	var mode: Int32 = 0
	var overrideConsoleSerialPort: Bool = false
	var rxd: Int32 = 0
	var timeout: Int32 = 0
	var txd: Int32 = 0
	var serialConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class StoreForwardConfigEntity {
	var enabled: Bool = false
	var heartbeat: Bool = false
	var historyReturnMax: Int32 = 0
	var historyReturnWindow: Int32 = 0
	var isRouter: Bool = false
	var lastHeartbeat: Date?
	var lastRequest: Int32 = 0
	var records: Int32 = 0
	var storeForwardConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class StatusMessageConfigEntity {
	var nodeStatus: String = ""
	var statusMessageConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class TAKConfigEntity {
	var role: Int32 = 0
	var team: Int32 = 0
	var takConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class TrafficManagementConfigEntity {
	var enabled: Bool = false
	var positionDedupEnabled: Bool = false
	var positionPrecisionBits: Int32 = 0
	var positionMinIntervalSecs: Int32 = 0
	var nodeinfoDirectResponse: Bool = false
	var nodeinfoDirectResponseMaxHops: Int32 = 0
	var rateLimitEnabled: Bool = false
	var rateLimitWindowSecs: Int32 = 0
	var rateLimitMaxPackets: Int32 = 0
	var dropUnknownEnabled: Bool = false
	var unknownPacketThreshold: Int32 = 0
	var exhaustHopTelemetry: Bool = false
	var exhaustHopPosition: Bool = false
	var routerPreserveHops: Bool = false
	var trafficManagementConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class TelemetryConfigEntity {
	var airQualityEnabled: Bool = false
	var airQualityInterval: Int32 = 0
	var deviceTelemetryEnabled: Bool = false
	var deviceUpdateInterval: Int32 = 0
	var environmentDisplayFahrenheit: Bool = false
	var environmentMeasurementEnabled: Bool = false
	var environmentScreenEnabled: Bool = false
	var environmentUpdateInterval: Int32 = 0
	var powerMeasurementEnabled: Bool = false
	var powerScreenEnabled: Bool = false
	var powerUpdateInterval: Int32 = 0
	var telemetryConfigNode: NodeInfoEntity?

	init() {}
}
