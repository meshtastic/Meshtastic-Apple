//
//  TeamStatusBoard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/24/26.
//
#if os(visionOS)
import CoreLocation
import SwiftData
import SwiftUI

/// The live team roster on the tent's whiteboard in the cinema: the connected radio and the
/// favorite nodes, with when each was last heard, its battery, signal, hops, and distance and
/// bearing from the radio. Drawn as marker on the board, to be read from across the tent.
/// Tapping a row centers the 3D map on the node and opens its detail on the front screen.
struct TeamStatusBoard: View {
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Environment(\.openWindow) private var openWindow
	@State private var roster: Roster?

	/// The board's size in points. CinemaSpace scales the panel to the board in the image, so only
	/// the 3:2 shape matters.
	static let size = CGSize(width: 1800, height: 1200)
	private static let maxRows = 8
	/// How often the rows are read from the store. The board is read from across the tent, so a
	/// few seconds late is fine, and it keeps the store work off every packet.
	private static let refreshInterval: Duration = .seconds(5)

	var body: some View {
		// A ZStack, not a Group: the modifiers below on an empty Group attach to nothing, so the
		// task that reads the first roster would never start.
		ZStack {
			if let roster {
				content(roster)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.padding(.horizontal, 56)
		.padding(.vertical, 44)
		.frame(width: Self.size.width, height: Self.size.height)
		.background(BoardStyle.surface)
		.environment(\.colorScheme, .light)
		.task(id: RadioKey(isConnected: accessoryManager.isConnected, num: accessoryManager.activeDeviceNum)) {
			while !Task.isCancelled {
				// The reset can start while this sleeps; don't read rows that are being deleted.
				if !appState.isDatabaseResetting {
					roster = makeRoster()
				}
				try? await Task.sleep(for: Self.refreshInterval)
			}
		}
	}

	@ViewBuilder
	private func content(_ roster: Roster) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			title(radioName: roster.radioName)
			if roster.members.isEmpty {
				emptyState
			} else {
				headerRow
					.padding(.top, 28)
				Rectangle()
					.fill(BoardStyle.ink)
					.frame(height: 5)
					.padding(.top, 8)
				ForEach(roster.members) { member in
					Button {
						show(member.id)
					} label: {
						TeamRow(member: member, now: roster.date)
					}
					.buttonStyle(.plain)
					.hoverEffect(.highlight)
				}
				Spacer(minLength: 0)
				footer(roster)
			}
		}
	}

	// MARK: Pieces

	private func title(radioName: String?) -> some View {
		HStack(alignment: .firstTextBaseline) {
			Text("Team Status", comment: "Cinema: title of the live team roster on the tent's whiteboard")
				.textCase(.uppercase)
				.font(BoardStyle.marker(92))
				.foregroundStyle(BoardStyle.blue)
			Spacer()
			if let radioName {
				HStack(spacing: 14) {
					Image(systemName: TeamMember.Status.connected.symbol)
						.font(.system(size: 36, weight: .bold))
						.foregroundStyle(BoardStyle.green)
						.accessibilityHidden(true)
					Text(verbatim: radioName)
						.font(BoardStyle.marker(46))
						.foregroundStyle(BoardStyle.ink)
						.lineLimit(1)
				}
			} else {
				HStack(spacing: 14) {
					Image(systemName: "exclamationmark.triangle.fill")
						.font(.system(size: 36, weight: .bold))
						.accessibilityHidden(true)
					Text("No radio connected", comment: "Cinema team board: shown in the corner when no radio is connected")
						.font(BoardStyle.marker(46))
				}
				.foregroundStyle(BoardStyle.red)
			}
			MeshLogo(height: 44)
				.padding(.leading, 18)
		}
	}

	private var headerRow: some View {
		HStack(spacing: TeamRow.spacing) {
			Text("Node")
				.frame(width: TeamRow.nameWidth, alignment: .leading)
			Text("Last heard")
				.frame(width: TeamRow.heardWidth, alignment: .leading)
			Text("Battery")
				.frame(width: TeamRow.batteryWidth, alignment: .leading)
			Text("Signal", comment: "Cinema team board: column header for the node's signal bars")
				.frame(width: TeamRow.signalWidth, alignment: .leading)
			Text("Hops")
				.frame(width: TeamRow.hopsWidth, alignment: .leading)
			Text("Distance")
				.frame(maxWidth: .infinity, alignment: .leading)
		}
		.textCase(.uppercase)
		.font(BoardStyle.marker(38))
		.foregroundStyle(BoardStyle.ink)
		.lineLimit(1)
		.minimumScaleFactor(0.6)
	}

	@ViewBuilder
	private func footer(_ roster: Roster) -> some View {
		if roster.hiddenCount > 0 {
			Text("+\(roster.hiddenCount) more", comment: "Cinema team board: how many favorite nodes didn't fit on the board")
				.font(BoardStyle.marker(40))
				.foregroundStyle(BoardStyle.faded)
		} else if roster.favoriteCount == 0 {
			Text("Favorite nodes to add them to the board.", comment: "Cinema team board: hint shown when only the connected radio is listed")
				.font(BoardStyle.marker(40))
				.foregroundStyle(BoardStyle.faded)
		}
	}

	private var emptyState: some View {
		VStack(spacing: 24) {
			Spacer()
			Text("No team yet", comment: "Cinema team board: shown when there's no radio connected and no favorite nodes")
				.font(BoardStyle.marker(80))
				.foregroundStyle(BoardStyle.blue)
			Text("Connect a radio and favorite the nodes you're tracking to list them here.", comment: "Cinema team board: how to fill the empty board")
				.font(BoardStyle.marker(46))
				.foregroundStyle(BoardStyle.ink)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 1200)
			Spacer()
		}
		.frame(maxWidth: .infinity)
	}

	// MARK: Data

	/// What the rows are read for. A new radio rebuilds the board right away.
	private struct RadioKey: Equatable {
		let isConnected: Bool
		let num: Int64?
	}

	/// The rows as last read from the store.
	private struct Roster {
		let date: Date
		let radioName: String?
		let members: [TeamMember]
		/// Favorites other than the radio, shown or not.
		let favoriteCount: Int
		let hiddenCount: Int
	}

	/// Reads the radio and the favorites that fit on the board, most recently heard first. Only
	/// the rows shown are looked up further, so the work doesn't grow with the favorites.
	private func makeRoster() -> Roster {
		let radio = accessoryManager.isConnected ? accessoryManager.activeDeviceNum.flatMap { getNodeInfo(id: $0, context: context) } : nil
		// No node has a negative number, so this matches every favorite when there's no radio.
		let radioNum = radio?.num ?? -1
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.favorite == true && $0.num != radioNum },
			sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
		)
		let favoriteCount = (try? context.fetchCount(descriptor)) ?? 0
		descriptor.fetchLimit = Self.maxRows - (radio == nil ? 0 : 1)
		let favorites = (try? context.fetch(descriptor)) ?? []

		var members: [TeamMember] = []
		if let radio {
			let preset = (radio.loRaConfig?.modemPreset).flatMap { ModemPresets(rawValue: Int($0)) } ?? .longFast
			let noiseFloor = favorites.isEmpty ? nil : radio.recentNoiseFloor
			let radioLocation = favorites.isEmpty ? nil : radio.latestPosition?.nodeCoordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
			members.append(member(radio, isRadio: true, preset: preset, noiseFloor: nil, radioLocation: nil))
			for node in favorites {
				members.append(member(node, isRadio: false, preset: preset, noiseFloor: noiseFloor, radioLocation: radioLocation))
			}
		} else {
			for node in favorites {
				members.append(member(node, isRadio: false, preset: .longFast, noiseFloor: nil, radioLocation: nil))
			}
		}
		return Roster(
			date: .now,
			radioName: radio.map { $0.liveUser?.longName ?? hexName($0.num) },
			members: members,
			favoriteCount: favoriteCount,
			hiddenCount: max(0, favoriteCount - favorites.count)
		)
	}

	private func member(_ node: NodeInfoEntity, isRadio: Bool, preset: ModemPresets, noiseFloor: Int32?, radioLocation: CLLocation?) -> TeamMember {
		let user = node.liveUser
		// Signal only for nodes the radio hears directly, and never over MQTT: the same gate as
		// the Live Activity.
		var signal: Int?
		if !isRadio, node.snr != 0, !node.viaMqtt, node.hopsAway == 0 {
			signal = getLoRaSignalStrength(snr: node.snr, rssi: node.rssi, preset: preset, noiseFloor: noiseFloor).rawValue
		}
		var distance: Double?
		var bearing: Double?
		if let radioLocation, let coordinate = node.latestPosition?.nodeCoordinate {
			let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
			distance = location.distance(from: radioLocation)
			let degrees = getBearingBetweenTwoPoints(point1: radioLocation, point2: location)
			bearing = (degrees + 360).truncatingRemainder(dividingBy: 360)
		}
		let status: TeamMember.Status = if isRadio {
			.connected
		} else if node.lastHeard == nil {
			.neverHeard
		} else {
			node.isOnline ? .heard : .stale
		}
		return TeamMember(
			id: node.num,
			shortName: user?.shortName ?? String(hexName(node.num).suffix(4)),
			longName: user?.longName ?? hexName(node.num),
			lastHeard: node.lastHeard,
			status: status,
			batteryLevel: node.latestDeviceMetrics?.batteryLevel,
			signalRating: signal,
			hopsAway: node.viaMqtt ? nil : node.hopsAway,
			distance: distance,
			bearing: bearing
		)
	}

	private func hexName(_ num: Int64) -> String {
		"!" + String(format: "%08x", UInt32(truncatingIfNeeded: num))
	}

	/// Centers the 3D map on the node, opening the map if it isn't open (an open one comes
	/// forward), and puts the node's detail on the front screen.
	private func show(_ nodeNum: Int64) {
		appState.spatialMapFocus = SpatialMapFocusRequest(nodeNum: nodeNum)
		openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
		appState.cinemaScreenRequest = .node(nodeNum)
	}
}

/// One row's values, read from the store when the board refreshes.
private struct TeamMember: Identifiable {
	enum Status {
		/// The connected radio.
		case connected
		/// Heard in the last two hours.
		case heard
		/// Heard, but not in the last two hours.
		case stale
		case neverHeard

		/// Shown beside the last-heard time, so status doesn't rest on color alone.
		var symbol: String {
			switch self {
			case .connected: "link"
			case .heard: "checkmark.circle.fill"
			case .stale: "exclamationmark.triangle.fill"
			case .neverHeard: "questionmark.circle"
			}
		}

		var color: Color {
			switch self {
			case .connected: BoardStyle.green
			case .heard: BoardStyle.ink
			case .stale: BoardStyle.red
			case .neverHeard: BoardStyle.faded
			}
		}
	}

	let id: Int64
	let shortName: String
	let longName: String
	let lastHeard: Date?
	let status: Status
	let batteryLevel: Int32?
	let signalRating: Int?
	/// Nil for a node heard over MQTT, where hops don't apply.
	let hopsAway: Int32?
	let distance: Double?
	let bearing: Double?
}

private struct TeamRow: View {
	let member: TeamMember
	let now: Date

	static let spacing: CGFloat = 16
	static let nameWidth: CGFloat = 450
	static let heardWidth: CGFloat = 300
	static let batteryWidth: CGFloat = 210
	static let signalWidth: CGFloat = 130
	static let hopsWidth: CGFloat = 190

	/// Nodes not heard lately are written in the faded ink, which still reads at full contrast.
	private var ink: Color {
		switch member.status {
		case .connected, .heard: BoardStyle.ink
		case .stale, .neverHeard: BoardStyle.faded
		}
	}

	var body: some View {
		HStack(spacing: Self.spacing) {
			HStack(spacing: 22) {
				NodeChip(shortName: member.shortName, colorSeed: UInt32(truncatingIfNeeded: member.id), size: 78)
				Text(verbatim: member.longName)
					.font(BoardStyle.marker(50))
					.foregroundStyle(member.status == .connected ? BoardStyle.blue : ink)
					.lineLimit(1)
					.minimumScaleFactor(0.6)
			}
			.frame(width: Self.nameWidth, alignment: .leading)

			cell(width: Self.heardWidth) { heard }
			cell(width: Self.batteryWidth) {
				BatteryRow(level: member.batteryLevel, font: BoardStyle.marker(42), color: ink)
			}
			cell(width: Self.signalWidth) {
				SignalBars(rating: member.signalRating, font: .system(size: 46))
			}
			cell(width: Self.hopsWidth) { hops }
			cell(width: nil) { distance }
		}
		.font(BoardStyle.marker(42))
		.foregroundStyle(ink)
		.lineLimit(1)
		.minimumScaleFactor(0.6)
		.padding(.vertical, 8)
		.frame(height: 104)
		.overlay(alignment: .bottom) {
			Rectangle()
				.fill(BoardStyle.ink.opacity(0.3))
				.frame(height: 3)
		}
		.contentShape(Rectangle())
		.accessibilityElement(children: .combine)
	}

	/// A column that keeps its width when its value is missing. Battery and signal draw nothing
	/// without a value, and a frame on nothing takes no space.
	private func cell(width: CGFloat?, @ViewBuilder content: () -> some View) -> some View {
		HStack(spacing: 0) {
			content()
			Spacer(minLength: 0)
		}
		.frame(width: width)
		.frame(maxWidth: width == nil ? .infinity : nil)
	}

	private var heard: some View {
		HStack(spacing: 12) {
			Image(systemName: member.status.symbol)
				.font(.system(size: 32, weight: .bold))
				.accessibilityHidden(true)
			switch member.status {
			case .connected:
				Text("Connected")
			case .neverHeard:
				Text("Never heard")
			case .heard, .stale:
				// Moves on with the board's refresh, not every second.
				Text(verbatim: (member.lastHeard ?? now).formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
			}
		}
		.foregroundStyle(member.status.color)
	}

	@ViewBuilder
	private var hops: some View {
		if member.status == .connected {
			Text("Base", comment: "Cinema team board: the hops column for the connected radio, the base distances are measured from")
				.foregroundStyle(BoardStyle.blue)
		} else if member.status == .neverHeard {
			// Hops default to zero until the node is heard, which isn't "Direct".
			Text(verbatim: "—")
		} else if let hopsAway = member.hopsAway {
			if hopsAway == 0 {
				Text("Direct")
			} else {
				Text(verbatim: "\(hopsAway)")
			}
		} else {
			Text(verbatim: "MQTT")
		}
	}

	@ViewBuilder
	private var distance: some View {
		if let distance = member.distance {
			HStack(spacing: 12) {
				Text(verbatim: Measurement(value: distance, unit: UnitLength.meters)
					.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1)))))
				if let bearing = member.bearing {
					Image(systemName: "location.north.fill")
						.font(.system(size: 30))
						.rotationEffect(.degrees(bearing))
						.foregroundStyle(BoardStyle.blue)
						.accessibilityHidden(true)
					Text(verbatim: "\(Int(bearing.rounded()) % 360)°")
				}
			}
		} else {
			Text(verbatim: "—")
		}
	}
}

/// Marker on a whiteboard. The surface matches the blank board in the tent image, which has a
/// light on it so it is this light, and every ink below reads at a WCAG contrast of at least 4.5:1
/// across the gradient.
/// Top / bottom: ink 7.8 / 6.6, blue 6.8 / 5.7, red 5.7 / 4.8, green 5.7 / 4.8, faded 5.6 / 4.7.
private enum BoardStyle {
	static let surface = LinearGradient(
		colors: [Color(red: 184 / 255, green: 164 / 255, blue: 134 / 255), Color(red: 170 / 255, green: 150 / 255, blue: 121 / 255)],
		startPoint: .top,
		endPoint: .bottom
	)
	static let ink = Color(red: 0.07, green: 0.07, blue: 0.08)
	static let blue = Color(red: 0.04, green: 0.10, blue: 0.33)
	static let red = Color(red: 0.38, green: 0.02, blue: 0.02)
	static let green = Color(red: 0, green: 0.21, blue: 0.07)
	/// Nodes not heard lately, hints and missing values.
	static let faded = Color(red: 0.19, green: 0.18, blue: 0.17)

	/// The board's handwriting, falling back to the system font where Chalkboard isn't installed.
	static func marker(_ size: CGFloat) -> Font {
		.custom("ChalkboardSE-Regular", fixedSize: size)
	}
}
#endif
