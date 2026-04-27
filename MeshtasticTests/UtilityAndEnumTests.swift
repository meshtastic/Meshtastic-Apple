import Foundation
import Testing

@testable import Meshtastic

// MARK: - CommonRegex

@Suite("CommonRegex COORDS_REGEX")
struct CommonRegexTests {

	@Test func matches_validCoords() {
		let text = "lat=12345678 long=87654321"
		let match = text.firstMatch(of: CommonRegex.COORDS_REGEX)
		#expect(match != nil)
	}

	@Test func matches_singleDigit() {
		let text = "lat=0 long=1"
		let match = text.firstMatch(of: CommonRegex.COORDS_REGEX)
		#expect(match != nil)
	}

	@Test func noMatch_missingLat() {
		let text = "long=12345"
		let match = text.firstMatch(of: CommonRegex.COORDS_REGEX)
		#expect(match == nil)
	}

	@Test func noMatch_missingLong() {
		let text = "lat=12345"
		let match = text.firstMatch(of: CommonRegex.COORDS_REGEX)
		#expect(match == nil)
	}

	@Test func noMatch_randomText() {
		let text = "Hello World"
		let match = text.firstMatch(of: CommonRegex.COORDS_REGEX)
		#expect(match == nil)
	}
}

// MARK: - NavigationState

@Suite("NavigationState Extended")
struct NavigationStateExtendedTests {

	@Test func defaultTab_isConnect() {
		let state = NavigationState()
		#expect(state.selectedTab == .connect)
	}

	@Test func tab_rawValues() {
		#expect(NavigationState.Tab.messages.rawValue == "messages")
		#expect(NavigationState.Tab.connect.rawValue == "connect")
		#expect(NavigationState.Tab.nodes.rawValue == "nodes")
		#expect(NavigationState.Tab.map.rawValue == "map")
		#expect(NavigationState.Tab.settings.rawValue == "settings")
	}

	@Test func messagesState_channels() {
		let state = MessagesNavigationState.channels(channelId: 5, messageId: 100)
		if case .channels(let ch, let msg) = state {
			#expect(ch == 5)
			#expect(msg == 100)
		} else {
			#expect(Bool(false))
		}
	}

	@Test func messagesState_directMessages() {
		let state = MessagesNavigationState.directMessages(userNum: 42, messageId: 7)
		if case .directMessages(let user, let msg) = state {
			#expect(user == 42)
			#expect(msg == 7)
		} else {
			#expect(Bool(false))
		}
	}

	@Test func mapState_selectedNode() {
		let state = MapNavigationState.selectedNode(123)
		if case .selectedNode(let id) = state {
			#expect(id == 123)
		} else {
			#expect(Bool(false))
		}
	}

	@Test func mapState_waypoint() {
		let state = MapNavigationState.waypoint(456)
		if case .waypoint(let id) = state {
			#expect(id == 456)
		} else {
			#expect(Bool(false))
		}
	}

	@Test func settingsState_allRawValues() {
		let cases: [(SettingsNavigationState, String)] = [
			(.about, "about"),
			(.appSettings, "appSettings"),
			(.routes, "routes"),
			(.routeRecorder, "routeRecorder"),
			(.lora, "lora"),
			(.channels, "channels"),
			(.shareQRCode, "shareQRCode"),
			(.user, "user"),
			(.bluetooth, "bluetooth"),
			(.device, "device"),
			(.display, "display"),
			(.network, "network"),
			(.position, "position"),
			(.power, "power"),
			(.ambientLighting, "ambientLighting"),
			(.cannedMessages, "cannedMessages"),
			(.detectionSensor, "detectionSensor"),
			(.externalNotification, "externalNotification"),
			(.mqtt, "mqtt"),
			(.rangeTest, "rangeTest"),
			(.paxCounter, "paxCounter"),
			(.ringtone, "ringtone"),
			(.serial, "serial"),
			(.security, "security"),
			(.storeAndForward, "storeAndForward"),
			(.telemetry, "telemetry"),
			(.debugLogs, "debugLogs"),
			(.appFiles, "appFiles"),
			(.firmwareUpdates, "firmwareUpdates"),
			(.tak, "tak"),
			(.takConfig, "takConfig"),
			(.tools, "tools"),
		]
		for (setting, expected) in cases {
			#expect(setting.rawValue == expected)
		}
	}

	@Test func settingsState_initFromRawValue() {
		#expect(SettingsNavigationState(rawValue: "about") == .about)
		#expect(SettingsNavigationState(rawValue: "lora") == .lora)
		#expect(SettingsNavigationState(rawValue: "invalid") == nil)
	}

	@Test func navigationState_hashable() {
		let state1 = NavigationState(selectedTab: .connect)
		let state2 = NavigationState(selectedTab: .connect)
		#expect(state1 == state2)

		let state3 = NavigationState(selectedTab: .messages)
		#expect(state1 != state3)
	}

	@Test func navigationState_withAllFields() {
		let state = NavigationState(
			selectedTab: .messages,
			messages: .channels(channelId: 1),
			nodeListSelectedNodeNum: 42,
			map: .selectedNode(10),
			settings: .about
		)
		#expect(state.selectedTab == .messages)
		#expect(state.nodeListSelectedNodeNum == 42)
		#expect(state.settings == .about)
	}
}

// MARK: - BubblePosition

@Suite("BubblePosition")
struct BubblePositionTests {

	@Test func left_and_right_exist() {
		let left = BubblePosition.left
		let right = BubblePosition.right
		#expect(left != right)
	}
}

// MARK: - Tapbacks Extended

@Suite("Tapbacks Emoji Mapping")
struct TapbacksEmojiTests {

	@Test func allCases_haveEmojiStrings() {
		for tapback in Tapbacks.allCases {
			#expect(!tapback.emojiString.isEmpty)
		}
	}

	@Test func wave_isWaveEmoji() {
		#expect(Tapbacks.wave.emojiString == "👋")
	}

	@Test func heart_isHeartEmoji() {
		#expect(Tapbacks.heart.emojiString == "❤️")
	}

	@Test func thumbsUp_emoji() {
		#expect(Tapbacks.thumbsUp.emojiString == "👍")
	}

	@Test func thumbsDown_emoji() {
		#expect(Tapbacks.thumbsDown.emojiString == "👎")
	}

	@Test func haHa_emoji() {
		#expect(Tapbacks.haHa.emojiString == "🤣")
	}

	@Test func poop_emoji() {
		#expect(Tapbacks.poop.emojiString == "💩")
	}

	@Test func id_matchesRawValue() {
		for tapback in Tapbacks.allCases {
			#expect(tapback.id == tapback.rawValue)
		}
	}
}

// MARK: - Aqi Extended

@Suite("AQI getAqi")
struct AqiGetAqiTests {

	@Test func zeroIsGood() {
		#expect(Aqi.getAqi(for: 0) == .good)
	}

	@Test func fiftyIsGood() {
		#expect(Aqi.getAqi(for: 50) == .good)
	}

	@Test func fiftyOneIsModerate() {
		#expect(Aqi.getAqi(for: 51) == .moderate)
	}

	@Test func hundredIsModerate() {
		#expect(Aqi.getAqi(for: 100) == .moderate)
	}

	@Test func sensitive_range() {
		#expect(Aqi.getAqi(for: 101) == .sensitive)
		#expect(Aqi.getAqi(for: 150) == .sensitive)
	}

	@Test func unhealthy_range() {
		#expect(Aqi.getAqi(for: 151) == .unhealthy)
		#expect(Aqi.getAqi(for: 200) == .unhealthy)
	}

	@Test func veryUnhealthy_range() {
		#expect(Aqi.getAqi(for: 201) == .veryUnhealthy)
		#expect(Aqi.getAqi(for: 300) == .veryUnhealthy)
	}

	@Test func hazardous_range() {
		#expect(Aqi.getAqi(for: 301) == .hazardous)
		#expect(Aqi.getAqi(for: 500) == .hazardous)
	}

	@Test func allCases_haveRanges() {
		for aqi in Aqi.allCases {
			#expect(!aqi.range.isEmpty)
		}
	}
}

// MARK: - Iaq Extended

@Suite("IAQ getIaq")
struct IaqGetIaqTests {

	@Test func zeroIsExcellent() {
		#expect(Iaq.getIaq(for: 0) == .excellent)
	}

	@Test func fiftyIsExcellent() {
		#expect(Iaq.getIaq(for: 50) == .excellent)
	}

	@Test func fiftyOneIsGood() {
		#expect(Iaq.getIaq(for: 51) == .good)
	}

	@Test func lightlyPolluted_range() {
		#expect(Iaq.getIaq(for: 101) == .lightlyPolluted)
		#expect(Iaq.getIaq(for: 150) == .lightlyPolluted)
	}

	@Test func moderatelyPolluted_range() {
		#expect(Iaq.getIaq(for: 151) == .moderatelyPolluted)
		#expect(Iaq.getIaq(for: 200) == .moderatelyPolluted)
	}

	@Test func heavilyPolluted_range() {
		#expect(Iaq.getIaq(for: 201) == .heavilyPolluted)
		#expect(Iaq.getIaq(for: 250) == .heavilyPolluted)
	}

	@Test func severelyPolluted_range() {
		#expect(Iaq.getIaq(for: 251) == .severelyPolluted)
		#expect(Iaq.getIaq(for: 350) == .severelyPolluted)
	}

	@Test func extremelyPolluted_range() {
		#expect(Iaq.getIaq(for: 351) == .extremelyPolluted)
		#expect(Iaq.getIaq(for: 500) == .extremelyPolluted)
	}

	@Test func allCases_haveRanges() {
		for iaq in Iaq.allCases {
			#expect(!iaq.range.isEmpty)
		}
	}
}

// MARK: - WeatherConditions

@Suite("WeatherConditions Symbols")
struct WeatherConditionsSymbolTests {

	@Test func allCases_haveSymbolNames() {
		for condition in WeatherConditions.allCases {
			#expect(!condition.symbolName.isEmpty)
		}
	}

	@Test func clear_symbolIsSpark() {
		#expect(WeatherConditions.clear.symbolName == "sparkle")
	}

	@Test func rain_symbolHasCloud() {
		#expect(WeatherConditions.rain.symbolName.contains("rain"))
	}

	@Test func snow_symbolHasSnow() {
		#expect(WeatherConditions.snow.symbolName.contains("snow"))
	}

	@Test func smoky_symbolHasSmoke() {
		#expect(WeatherConditions.smoky.symbolName.contains("smoke"))
	}
}

// MARK: - TriggerTypes

@Suite("TriggerTypes Names")
struct TriggerTypesNameTests {

	@Test func allCases_haveNames() {
		for trigger in TriggerTypes.allCases {
			#expect(!trigger.name.isEmpty)
		}
	}

	@Test func logicLow_name() {
		#expect(TriggerTypes.logicLow.name == "Low")
	}

	@Test func risingEdge_name() {
		#expect(TriggerTypes.risingEdge.name == "Rising Edge")
	}

	@Test func allCases_haveProtoValues() {
		for trigger in TriggerTypes.allCases {
			let _ = trigger.protoEnumValue()
		}
	}
}

// MARK: - MetricsTypes

@Suite("MetricsTypes Names")
struct MetricsTypesNameTests {

	@Test func allCases_haveNames() {
		for mt in MetricsTypes.allCases {
			#expect(!mt.name.isEmpty)
		}
	}

	@Test func device_isZero() {
		#expect(MetricsTypes.device.rawValue == 0)
	}

	@Test func environment_isOne() {
		#expect(MetricsTypes.environment.rawValue == 1)
	}
}
