//
//  DeviceConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import OSLog
import SwiftUI
import MeshtasticProtobufs

extension Config.DeviceConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, DeviceConfigEntity?> = \NodeInfoEntity.deviceConfig

	init(entity: DeviceConfigEntity) {
		self.init()
		role = Role(rawValue: Int(entity.role)) ?? .client
		buttonGpio = UInt32(truncatingIfNeeded: entity.buttonGpio)
		buzzerGpio = UInt32(truncatingIfNeeded: entity.buzzerGpio)
		rebroadcastMode = RebroadcastMode(rawValue: Int(entity.rebroadcastMode)) ?? .all
		nodeInfoBroadcastSecs = UInt32(truncatingIfNeeded: entity.nodeInfoBroadcastSecs)
		doubleTapAsButtonPress = entity.doubleTapAsButtonPress
		// The entity stores both of these as the positive sense.
		disableTripleClick = !entity.tripleClickAsAdHocPing
		ledHeartbeatDisabled = !entity.ledHeartbeatEnabled
		tzdef = entity.tzdef ?? ""
	}
}

struct DeviceConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	let node: NodeInfoEntity?
	@State private var isResetting = false

	private typealias F = Config.DeviceConfig.Fields

	static func overlay() -> ConfigFormOverlay<Config.DeviceConfig> {
		.init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				// The role picker warns before a router-class role is chosen, so it is its own control.
				.init(F.role, control: .custom { config in AnyView(DeviceRolePicker(role: config.role)) }),
				.init(F.rebroadcastMode),
				.init(F.nodeInfoBroadcastSecs, control: .interval(.broadcastLong))
			]),
			.init(title: String(localized: "Hardware", comment: "Settings section"), fields: [
				.init(F.doubleTapAsButtonPress, symbol: "hand.tap"),
				// Labelled upstream as the negative it is, so no inversion.
				.init(F.disableTripleClick, symbol: "mappin"),
				// Labelled "LED Heartbeat" upstream, so the toggle shows the positive sense.
				.init(F.ledHeartbeatDisabled, symbol: "waveform.path.ecg", inverted: true)
			]),
			.init(title: String(localized: "Debug", comment: "Settings section"), fields: [
				.init(F.tzdef, symbol: "clock.badge.exclamationmark", byteCap: 63)
			]),
			.init(title: String(localized: "GPIO", comment: "Settings section"), fields: [
				.init(F.buttonGpio, control: .gpioPin),
				.init(F.buzzerGpio, control: .gpioPin)
			])
		], omitted: [
			.init(F.buzzerMode, "not yet offered by this client; unlabelled upstream")
		])
	}

	/// Router Client was retired; a node still on it is shown and saved as Client Mute. The
	/// node-info interval floor is the firmware's own minimum.
	static func normalize(_ config: Config.DeviceConfig) -> Config.DeviceConfig {
		var c = config
		if c.role == .routerClient { c.role = .clientMute }
		if c.nodeInfoBroadcastSecs < 10800 { c.nodeInfoBroadcastSecs = 10800 }
		return c
	}

	var body: some View {
		if isResetting {
			VStack {
				ProgressView()
				Text("Resetting…").font(.caption).foregroundStyle(.secondary)
			}
		} else {
			MetadataConfigForm(
				node: node, title: "Device", overlay: Self.overlay(),
				normalize: Self.normalize,
				request: accessoryManager.requestDeviceConfig,
				save: { config, from, to in
					_ = try await accessoryManager.saveDeviceConfig(config: config, fromUser: from, toUser: to)
				},
				trailing: { _ in
					DeviceResetSection(node: node, isResetting: $isResetting, dismiss: goBack)
				})
			.navigationTitle("Device Config")
		}
	}
}

/// The role picker with the two things the plain picker cannot do: a warning before a
/// router-class role is chosen, and a note when the current role is retired.
private struct DeviceRolePicker: View {
	@Binding var role: Config.DeviceConfig.Role
	@State private var previous: Config.DeviceConfig.Role?
	@State private var pendingWarning: Config.DeviceConfig.Role?

	private static let enumName = "meshtastic.Config.DeviceConfig.Role"
	private static let warned: Set<Config.DeviceConfig.Role> = [.router, .routerLate, .clientBase]

	private func meta(_ r: Config.DeviceConfig.Role) -> FieldMetadata? { FieldMetadataRegistry.get(Self.enumName, tag: r.rawValue) }
	private var label: String { Config.DeviceConfig.Fields.role.metadata?.label ?? "Device Role" }

	/// The app's order, not declaration order; a retired role stays only while current.
	private var options: [Config.DeviceConfig.Role] {
		DeviceRoles.allCases.compactMap { Config.DeviceConfig.Role(rawValue: $0.rawValue) }
			.filter { $0 == role || meta($0)?.deprecated != true }
	}

	var body: some View {
		VStack(alignment: .leading) {
			Picker(label, selection: $role) {
				ForEach(options, id: \.self) { r in
					Text(meta(r)?.label ?? "\(r)").tag(r)
				}
			}
			if let description = meta(role)?.description {
				Text(description).foregroundColor(.gray).font(.callout)
			}
			if meta(role)?.deprecated == true {
				Label("This role is deprecated. Select a Router-based role to keep this node on a supported configuration.", systemImage: "exclamationmark.triangle")
					.foregroundColor(.orange)
					.font(.callout)
			}
		}
		.onAppear { previous = role }
		.onChange(of: role) { old, new in
			guard new != old else { return }
			if Self.warned.contains(new), pendingWarning == nil {
				pendingWarning = new
			} else {
				previous = new
			}
		}
		.confirmationDialog("Are you sure?", isPresented: Binding(get: { pendingWarning != nil }, set: { if !$0 { pendingWarning = nil } }), titleVisibility: .visible) {
			Button("Confirm") { previous = role; pendingWarning = nil }
			Button("Cancel", role: .cancel) { if let previous { role = previous }; pendingWarning = nil }
		} message: {
			Text(Self.warning(for: pendingWarning))
		}
	}

	private static func warning(for r: Config.DeviceConfig.Role?) -> String {
		switch r {
		case .router, .routerLate:
			return "The Router roles are only for high vantage locations like mountaintops and towers with few nearby nodes, not for use in urban areas. Improper use will hurt your local mesh."
		case .clientBase:
			return "Switching to Client Base will clear this node's favorites. Client Base should only favorite other nodes you control. Improper use will hurt your local mesh."
		default:
			return ""
		}
	}
}

/// Reset NodeDB and Factory Reset, for the connected radio only. Not configuration -
/// these are admin commands - so they sit below the form rather than in it.
private struct DeviceResetSection: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?
	@Binding var isResetting: Bool
	let dismiss: DismissAction
	@State private var confirmNodeDB = false
	@State private var confirmFactory = false

	private var isConnectedNode: Bool {
		accessoryManager.isConnected && node?.num == accessoryManager.activeConnection?.device.num
	}

	var body: some View {
		if isConnectedNode {
			Section {
				Button("Reset NodeDB", role: .destructive) { confirmNodeDB = true }
					.disabled(node?.user == nil)
					.confirmationDialog("Are you sure?", isPresented: $confirmNodeDB, titleVisibility: .visible) {
						Button("Reset node database, preserving favorites?") { reset(preserveFavorites: true) }
						Button("Reset node database and favorites?", role: .destructive) { reset(preserveFavorites: false) }
					}
				Button("Factory Reset", role: .destructive) { confirmFactory = true }
					.disabled(node?.user == nil)
					.confirmationDialog("Factory reset will delete device and app data.", isPresented: $confirmFactory, titleVisibility: .visible) {
						Button("Delete all config? ", role: .destructive) { factoryReset(resetDevice: false) }
						Button("Delete all config, keys and BLE bonds? ", role: .destructive) { factoryReset(resetDevice: true) }
					}
			}
		}
	}

	private func reset(preserveFavorites: Bool) {
		guard let user = node?.user else { return }
		isResetting = true
		Task {
			do {
				try await accessoryManager.sendNodeDBReset(fromUser: user, toUser: user, preserveFavorites: preserveFavorites)
				try await Task.sleep(for: .seconds(1))
				if let conn = accessoryManager.activeConnection {
					try await conn.connection.disconnect(withError: nil, shouldReconnect: true)
				}
				dismiss()
				try await Task.sleep(for: .milliseconds(500))
				await MeshPackets.shared.flushDebouncedSaves()
				await MeshPackets.shared.clearDatabase(includeRoutes: false, preserveFavorites: preserveFavorites)
				await AccessoryManager.shared.resetDatabaseAfterClear()
				clearNotifications()
			} catch {
				Logger.mesh.error("NodeDB Reset Failed")
				isResetting = false
			}
		}
	}

	private func factoryReset(resetDevice: Bool) {
		guard let user = node?.user else { return }
		isResetting = true
		Task {
			do {
				try await accessoryManager.sendFactoryReset(fromUser: user, toUser: user, resetDevice: resetDevice)
				try? await Task.sleep(for: .seconds(1))
				if resetDevice {
					try await accessoryManager.disconnect()
				} else if let conn = accessoryManager.activeConnection {
					try await conn.connection.disconnect(withError: nil, shouldReconnect: true)
				}
				dismiss()
				try await Task.sleep(for: .milliseconds(500))
				await MeshPackets.shared.flushDebouncedSaves()
				await MeshPackets.shared.clearDatabase(includeRoutes: false)
				await AccessoryManager.shared.resetDatabaseAfterClear()
				clearNotifications()
			} catch {
				Logger.mesh.error("Factory Reset Failed")
				isResetting = false
			}
		}
	}
}
