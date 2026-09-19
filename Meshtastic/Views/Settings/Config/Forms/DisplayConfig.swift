//
//  DisplayConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension Config.DisplayConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, DisplayConfigEntity?> = \NodeInfoEntity.displayConfig

	init(entity: DisplayConfigEntity) {
		self.init()
		screenOnSecs = UInt32(truncatingIfNeeded: entity.screenOnSeconds)
		autoScreenCarouselSecs = UInt32(truncatingIfNeeded: entity.screenCarouselInterval)
		compassNorthTop = entity.compassNorthTop
		compassOrientation = CompassOrientation(rawValue: Int(entity.compassOrientation)) ?? .degrees0
		wakeOnTapOrMotion = entity.wakeOnTapOrMotion
		flipScreen = entity.flipScreen
		oled = OledType(rawValue: Int(entity.oledType)) ?? .oledAuto
		displaymode = DisplayMode(rawValue: Int(entity.displayMode)) ?? .default
		units = DisplayUnits(rawValue: Int(entity.units)) ?? .metric
		headingBold = entity.headingBold
		use12HClock = entity.use12HClock
	}
}

struct DisplayConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = Config.DisplayConfig.Fields

	static func overlay() -> ConfigFormOverlay<Config.DisplayConfig> {
		let hasOrientation = ConfigFormCondition<Config.DisplayConfig>.firmware(atLeast: "2.3.13")
		return .init(sections: [
			.init(title: String(localized: "Device Screen", comment: "Settings section"), fields: [
				// Firmware before 2.3.13 has only the north-up toggle; later firmware has the
				// full orientation picker. Both fields are always saved.
				.init(F.compassOrientation, shownWhen: hasOrientation),
				.init(F.compassNorthTop, symbol: "location.north.circle", shownWhen: .not(hasOrientation)),
				.init(F.use12HClock, symbol: "clock"),
				.init(F.headingBold, symbol: "bold"),
				.init(F.units)
			]),
			.init(title: String(localized: "Timing and Overrides", comment: "Settings section"), fields: [
				.init(F.screenOnSecs, control: .options(ScreenOnIntervals.allCases.map { ConfigFormOption(value: $0.rawValue, title: $0.description) })),
				.init(F.autoScreenCarouselSecs, control: .options(ScreenCarouselIntervals.allCases.map { ConfigFormOption(value: $0.rawValue, title: $0.description) })),
				.init(F.wakeOnTapOrMotion, symbol: "gyroscope"),
				.init(F.flipScreen, symbol: "pip.swap"),
				.init(F.displaymode),
				// The two newest OLED types have no label upstream yet (protobufs#1103); offer
				// the four the screen always has until they do.
				.init(F.oled, enumValues: { _ in OledTypes.allCases.map(\.rawValue) })
			])
		], omitted: [
			.init(F.useLongNodeName, "not yet offered by this client; unlabelled upstream"),
			.init(F.enableMessageBubbles, "not yet offered by this client; unlabelled upstream")
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Display", overlay: Self.overlay(),
			request: accessoryManager.requestDisplayConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveDisplayConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Display Config")
	}
}
