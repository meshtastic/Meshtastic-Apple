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
	var dns: Int32 = 0
	var enabledProtocols: Int32 = 0
	var ethEnabled: Bool = false
	var gateway: Int32 = 0
	var ip: Int32 = 0
	var ntpServer: String?
	var subnet: Int32 = 0
	var wifiEnabled: Bool = false
	var wifiMode: Int32 = 0
	var wifiPsk: String?
	var wifiSsid: String?
	var networkConfigNode: NodeInfoEntity?

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
final class TAKConfigEntity {
	var role: Int32 = 0
	var team: Int32 = 0
	var takConfigNode: NodeInfoEntity?

	init() {}
}

@Model
final class TelemetryConfigEntity {
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
