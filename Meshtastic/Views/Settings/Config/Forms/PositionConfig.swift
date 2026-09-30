//
//  PositionConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import SwiftUI
import MeshtasticProtobufs
import OSLog

/// The bits of `PositionConfig.position_flags`. Raw values only: every label comes
/// from the flags' own enum value metadata in the schema.
struct PositionFlags: OptionSet, Sendable {
	let rawValue: Int
	static let Altitude = PositionFlags(rawValue: 1)
	static let AltitudeMsl = PositionFlags(rawValue: 2)
	static let GeoidalSeparation = PositionFlags(rawValue: 4)
	static let Dop = PositionFlags(rawValue: 8)
	static let Hvdop = PositionFlags(rawValue: 16)
	static let Satsinview = PositionFlags(rawValue: 32)
	static let SeqNo = PositionFlags(rawValue: 64)
	static let Timestamp = PositionFlags(rawValue: 128)
	static let Speed = PositionFlags(rawValue: 256)
	static let Heading = PositionFlags(rawValue: 512)
}

extension Config.PositionConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, PositionConfigEntity?> = \NodeInfoEntity.positionConfig

	init(entity: PositionConfigEntity) {
		self.init()
		positionBroadcastSecs = UInt32(truncatingIfNeeded: entity.positionBroadcastSeconds)
		positionBroadcastSmartEnabled = entity.smartPositionEnabled
		fixedPosition = entity.fixedPosition
		gpsUpdateInterval = UInt32(truncatingIfNeeded: entity.gpsUpdateInterval)
		positionFlags = UInt32(truncatingIfNeeded: entity.positionFlags)
		rxGpio = UInt32(truncatingIfNeeded: entity.rxGpio)
		txGpio = UInt32(truncatingIfNeeded: entity.txGpio)
		broadcastSmartMinimumDistance = UInt32(truncatingIfNeeded: entity.broadcastSmartMinimumDistance)
		broadcastSmartMinimumIntervalSecs = UInt32(truncatingIfNeeded: entity.broadcastSmartMinimumIntervalSecs)
		gpsEnGpio = UInt32(truncatingIfNeeded: entity.gpsEnGpio)
		gpsMode = GpsMode(rawValue: Int(entity.gpsMode)) ?? .notPresent
	}
}

struct PositionConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = Config.PositionConfig.Fields

	static func overlay(node: NodeInfoEntity? = nil) -> ConfigFormOverlay<Config.PositionConfig> {
		let smart = ConfigFormCondition<Config.PositionConfig>.isTrue(F.positionBroadcastSmartEnabled)
		let gpsOn = ConfigFormCondition<Config.PositionConfig>.equals(F.gpsMode, Config.PositionConfig.GpsMode.enabled)
		return .init(sections: [
			.init(title: String(localized: "Position Packet", comment: "Settings section"), fields: [
				.init(F.positionBroadcastSecs, control: .interval(.broadcastMedium)),
				.init(F.positionBroadcastSmartEnabled, symbol: "brain"),
				.init(F.broadcastSmartMinimumIntervalSecs, shownWhen: smart, control: .interval(.smartBroadcastMinimum)),
				// Every fifth metre of the range the firmware accepts, as the old screen
				// offered. A plain number field would let through values it rejects.
				.init(F.broadcastSmartMinimumDistance, shownWhen: smart,
					  control: .options(stride(from: 10, through: 150, by: 5).map {
						  ConfigFormOption(value: $0, title: "\($0)")
					  }))
			]),
			.init(title: String(localized: "Device GPS", comment: "Settings section"), fields: [
				.init(F.gpsMode, control: .segmented),
				.init(F.gpsUpdateInterval, shownWhen: gpsOn,
					  control: .options(GpsUpdateIntervals.allCases.map {
						  ConfigFormOption(value: $0.rawValue, title: $0.description)
					  })),
				// Setting a fixed position sends the phone's location to the radio, so the
				// row confirms first and reverts if the confirmation is declined.
				.init(F.fixedPosition, symbol: "location.square.fill",
					  shownWhen: .any([.not(gpsOn), .isTrue(F.fixedPosition)]),
					  control: .custom { config in AnyView(FixedPositionRow(config: config, node: node)) })
			]),
			// One entry, because a field is laid out once. The dependent bits nest by
			// condition instead of sitting in a second "Advanced" section, which would
			// mean laying position_flags out twice.
			.init(title: String(localized: "Position Flags", comment: "Settings section"), fields: [
				.init(F.positionFlags, control: .flags([
					.init(rawValue: PositionFlags.Altitude.rawValue, label: flagLabel(.Altitude), symbol: "arrow.up"),
					.init(rawValue: PositionFlags.AltitudeMsl.rawValue, label: flagLabel(.AltitudeMsl),
						  symbol: "arrow.up.to.line.compact",
						  shownWhen: .flag(F.positionFlags, UInt32(PositionFlags.Altitude.rawValue))),
					.init(rawValue: PositionFlags.GeoidalSeparation.rawValue, label: flagLabel(.GeoidalSeparation),
						  symbol: "globe.americas",
						  shownWhen: .flag(F.positionFlags, UInt32(PositionFlags.Altitude.rawValue))),
					.init(rawValue: PositionFlags.Satsinview.rawValue, label: flagLabel(.Satsinview), symbol: "skew"),
					.init(rawValue: PositionFlags.SeqNo.rawValue, label: flagLabel(.SeqNo), symbol: "number"),
					.init(rawValue: PositionFlags.Timestamp.rawValue, label: flagLabel(.Timestamp), symbol: "clock"),
					.init(rawValue: PositionFlags.Heading.rawValue, label: flagLabel(.Heading), symbol: "location.circle"),
					.init(rawValue: PositionFlags.Speed.rawValue, label: flagLabel(.Speed), symbol: "speedometer"),
					.init(rawValue: PositionFlags.Dop.rawValue, label: flagLabel(.Dop)),
					.init(rawValue: PositionFlags.Hvdop.rawValue, label: flagLabel(.Hvdop),
						  shownWhen: .flag(F.positionFlags, UInt32(PositionFlags.Dop.rawValue)))
				]))
			]),
			.init(title: String(localized: "Advanced Device GPS", comment: "Settings section"),
				  shownWhen: gpsOn, fields: [
				.init(F.rxGpio, control: .gpioPin),
				.init(F.txGpio, control: .gpioPin),
				.init(F.gpsEnGpio, control: .gpioPin)
			])
		], omitted: [
			// Firmware has migrated this into gps_mode and cleared it on load since
			// 2.5.14, which is the oldest firmware the app will connect to, so no radio
			// it talks to still reports it. Never read, never written.
			.init(F.gpsEnabled, "migrated into gps_mode by the firmware itself before the app's minimum version",
				  coveredBy: F.gpsMode.identity),
			.init(F.gpsAttemptTime, "not offered by this client; the firmware clamps it")
		])
	}

	private static func flagLabel(_ flag: PositionFlags) -> () -> String? {
		{ FieldMetadataRegistry.get("meshtastic.Config.PositionConfig.PositionFlags", tag: flag.rawValue)?.label }
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Position", overlay: Self.overlay(node: node),
			request: accessoryManager.requestPositionConfig,
			save: { config, from, to in
				_ = try await accessoryManager.savePositionConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Position Config")
	}
}

/// The fixed-position toggle. Turning it on sends the phone's current location to the
/// radio as its own admin message, and turning it off clears the stored position, so
/// both directions confirm first and put the switch back if the confirmation is
/// declined. The toggle itself still saves with the rest of the form.
private struct FixedPositionRow: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Binding var config: Config.PositionConfig
	let node: NodeInfoEntity?
	@State private var confirming = false

	private static let metadata = FieldMetadataRegistry.get("meshtastic.Config.PositionConfig", tag: 3)

	private var turningOn: Bool { config.fixedPosition }

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Toggle(isOn: $config.fixedPosition) {
				Label(Self.metadata?.label ?? "Fixed Position", systemImage: "location.square.fill")
			}
			if let description = Self.metadata?.description {
				Text(description)
					.foregroundColor(.gray)
					.font(.callout)
			}
		}
		.onChange(of: config.fixedPosition) { was, now in
			if was != now { confirming = true }
		}
		.alert(turningOn
			   ? String(localized: "Set Fixed Position", comment: "Alert title")
			   : String(localized: "Remove Fixed Position", comment: "Alert title"),
			   isPresented: $confirming) {
			Button(String(localized: "Cancel", comment: "Alert action"), role: .cancel) {
				config.fixedPosition.toggle()
			}
			if turningOn {
				Button(String(localized: "Set", comment: "Alert action")) { send(fixed: true) }
			} else {
				Button(String(localized: "Remove", comment: "Alert action"), role: .destructive) { send(fixed: false) }
			}
		} message: {
			Text(turningOn
				 ? "This will send a current position from your phone and enable fixed position."
				 : "This will disable fixed position and remove the currently set position.")
		}
	}

	/// Sends the change, and puts the switch back if it does not happen. The toggle has
	/// already moved by the time the alert is answered, so a failure that only logged
	/// would leave the form claiming a fixed position the radio never took, and the
	/// later config save would write that claim.
	///
	/// Resolve the user before the async hop and without force-unwraps: a device switch
	/// or node deletion mid-flow leaves it nil or invalidated, which crashed here in the
	/// field under Swift Concurrency.
	private func send(fixed: Bool) {
		guard let nodeNum = accessoryManager.activeDeviceNum, nodeNum > 0,
			  let user = node?.user, user.modelContext != nil else {
			Logger.mesh.error("Fixed position change failed - no live user for the connected node")
			config.fixedPosition = !fixed
			return
		}
		Task {
			do {
				if fixed {
					try await accessoryManager.setFixedPosition(fromUser: user, channel: 0)
				} else {
					try await accessoryManager.removeFixedPosition(fromUser: user, channel: 0)
				}
			} catch {
				Logger.mesh.error("Fixed position change failed")
				config.fixedPosition = !fixed
			}
		}
	}
}
