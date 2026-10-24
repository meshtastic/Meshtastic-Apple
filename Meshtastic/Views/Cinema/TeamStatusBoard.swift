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
/// bearing from the radio. Drawn as marker on the board, to be read from a couple of meters away.
/// Tapping a row opens the node in the app window.
struct TeamStatusBoard: View {
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Environment(\.openWindow) private var openWindow
	@Query(
		filter: #Predicate<NodeInfoEntity> { $0.favorite == true },
		sort: [SortDescriptor(\NodeInfoEntity.lastHeard, order: .reverse)]
	)
	private var favorites: [NodeInfoEntity]

	/// The board's size in points. CinemaSpace scales the panel to the board in the image, so only
	/// the 3:2 shape matters; at this size a point is about a millimeter.
	static let size = CGSize(width: 1800, height: 1200)
	private static let maxRows = 8

	var body: some View {
		TimelineView(.periodic(from: .now, by: 30)) { timeline in
			content(at: timeline.date)
		}
		.padding(.horizontal, 56)
		.padding(.vertical, 44)
		.frame(width: Self.size.width, height: Self.size.height)
		.background(BoardStyle.surface)
		.environment(\.colorScheme, .light)
	}

	@ViewBuilder
	private func content(at now: Date) -> some View {
		let radio = connectedRadio
		let members = teamMembers(radio: radio)
		VStack(alignment: .leading, spacing: 0) {
			title(radio: radio)
			if members.isEmpty {
				emptyState
			} else {
				headerRow
					.padding(.top, 28)
				Rectangle()
					.fill(BoardStyle.ink)
					.frame(height: 5)
					.padding(.top, 8)
				ForEach(members.prefix(Self.maxRows)) { member in
					Button {
						showInMainWindow(member.id)
					} label: {
						TeamRow(member: member, now: now)
					}
					.buttonStyle(.plain)
					.hoverEffect(.highlight)
				}
				Spacer(minLength: 0)
				footer(members: members, radio: radio)
			}
		}
	}

	// MARK: Pieces

	private func title(radio: NodeInfoEntity?) -> some View {
		HStack(alignment: .firstTextBaseline) {
			Text("Team Status", comment: "Cinema: title of the live team roster on the tent's whiteboard")
				.textCase(.uppercase)
				.font(BoardStyle.marker(92))
				.foregroundStyle(BoardStyle.blue)
			Spacer()
			if let radio {
				HStack(spacing: 14) {
					Circle()
						.fill(BoardStyle.green)
						.frame(width: 26, height: 26)
					Text(verbatim: radio.liveUser?.longName ?? hexName(radio.num))
						.font(BoardStyle.marker(46))
						.foregroundStyle(BoardStyle.ink)
						.lineLimit(1)
				}
			} else {
				Text("No radio connected", comment: "Cinema team board: shown in the corner when no radio is connected")
					.font(BoardStyle.marker(46))
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
	private func footer(members: [TeamMember], radio: NodeInfoEntity?) -> some View {
		let hidden = members.count - Self.maxRows
		if hidden > 0 {
			Text("+\(hidden) more", comment: "Cinema team board: how many favorite nodes didn't fit on the board")
				.font(BoardStyle.marker(40))
				.foregroundStyle(BoardStyle.ink.opacity(0.75))
		} else if favorites.isEmpty {
			Text("Favorite nodes to add them to the board.", comment: "Cinema team board: hint shown when only the connected radio is listed")
				.font(BoardStyle.marker(40))
				.foregroundStyle(BoardStyle.ink.opacity(0.75))
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

	/// The radio's node while it is connected. Distances are only measured from a radio that is
	/// connected now.
	private var connectedRadio: NodeInfoEntity? {
		guard accessoryManager.isConnected, let num = accessoryManager.activeDeviceNum else { return nil }
		return getNodeInfo(id: num, context: context)
	}

	/// The radio first, then favorites, most recently heard first.
	private func teamMembers(radio: NodeInfoEntity?) -> [TeamMember] {
		let preset = (radio?.loRaConfig?.modemPreset).flatMap { ModemPresets(rawValue: Int($0)) } ?? .longFast
		let noiseFloor = radio?.recentNoiseFloor
		let radioLocation = radio?.latestPosition?.nodeCoordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
		var members: [TeamMember] = []
		if let radio {
			members.append(member(radio, isRadio: true, preset: preset, noiseFloor: noiseFloor, radioLocation: nil))
		}
		for node in favorites where node.num != radio?.num {
			members.append(member(node, isRadio: false, preset: preset, noiseFloor: noiseFloor, radioLocation: radioLocation))
		}
		return members
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
		return TeamMember(
			id: node.num,
			shortName: user?.shortName ?? String(hexName(node.num).suffix(4)),
			longName: user?.longName ?? hexName(node.num),
			lastHeard: node.lastHeard,
			isOnline: node.isOnline,
			isRadio: isRadio,
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

	/// Hands the node to the main window, opening one if there is none.
	private func showInMainWindow(_ nodeNum: Int64) {
		guard let url = URL(string: "meshtastic:///nodes?nodenum=\(nodeNum)") else { return }
		appState.pendingRoute = PendingRoute(url: url, bringForward: true)
		if appState.mainWindowCount == 0 {
			openWindow(id: MeshtasticAppleApp.mainWindowID)
		}
	}
}

/// One row's values, read from the store when the board draws.
private struct TeamMember: Identifiable {
	let id: Int64
	let shortName: String
	let longName: String
	let lastHeard: Date?
	let isOnline: Bool
	let isRadio: Bool
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
	static let nameWidth: CGFloat = 560
	static let heardWidth: CGFloat = 250
	static let batteryWidth: CGFloat = 210
	static let signalWidth: CGFloat = 130
	static let hopsWidth: CGFloat = 130

	var body: some View {
		HStack(spacing: Self.spacing) {
			HStack(spacing: 22) {
				NodeChip(shortName: member.shortName, colorSeed: UInt32(truncatingIfNeeded: member.id), size: 78)
				Text(verbatim: member.longName)
					.font(BoardStyle.marker(50))
					.foregroundStyle(member.isRadio ? BoardStyle.blue : BoardStyle.ink)
					.lineLimit(1)
					.minimumScaleFactor(0.6)
			}
			.frame(width: Self.nameWidth, alignment: .leading)

			cell(width: Self.heardWidth) { heard }
			cell(width: Self.batteryWidth) {
				BatteryRow(level: member.batteryLevel, font: BoardStyle.marker(42), color: BoardStyle.ink)
			}
			cell(width: Self.signalWidth) {
				SignalBars(rating: member.signalRating, font: .system(size: 46))
			}
			cell(width: Self.hopsWidth) { hops }
			cell(width: nil) { distance }
		}
		.font(BoardStyle.marker(42))
		.foregroundStyle(BoardStyle.ink)
		.lineLimit(1)
		.minimumScaleFactor(0.6)
		.padding(.vertical, 8)
		.frame(height: 104)
		.opacity(member.isRadio || member.isOnline ? 1 : 0.55)
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

	@ViewBuilder
	private var heard: some View {
		if member.isRadio {
			Text("Connected")
				.foregroundStyle(BoardStyle.green)
		} else if let lastHeard = member.lastHeard {
			// Ticks with the board's timeline, not every second.
			Text(verbatim: lastHeard.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
				.foregroundStyle(member.isOnline ? BoardStyle.ink : BoardStyle.red)
		} else {
			Text("Never heard")
				.foregroundStyle(BoardStyle.red)
		}
	}

	@ViewBuilder
	private var hops: some View {
		if member.isRadio {
			Text("Base", comment: "Cinema team board: the hops column for the connected radio, the base distances are measured from")
				.foregroundStyle(BoardStyle.blue)
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
				.foregroundStyle(BoardStyle.ink.opacity(0.5))
		}
	}
}

/// Marker on a whiteboard. The surface is the blank board's color in the tent image, sampled at
/// its top and bottom, so the panel reads as the board rather than a window in front of it.
private enum BoardStyle {
	static let surface = LinearGradient(
		colors: [Color(red: 134 / 255, green: 110 / 255, blue: 82 / 255), Color(red: 110 / 255, green: 89 / 255, blue: 65 / 255)],
		startPoint: .top,
		endPoint: .bottom
	)
	static let ink = Color(red: 0.08, green: 0.08, blue: 0.09)
	static let blue = Color(red: 0.08, green: 0.16, blue: 0.45)
	static let red = Color(red: 0.55, green: 0.07, blue: 0.06)
	static let green = Color(red: 0.04, green: 0.33, blue: 0.14)

	/// The board's handwriting, falling back to the system font where Chalkboard isn't installed.
	static func marker(_ size: CGFloat) -> Font {
		.custom("ChalkboardSE-Regular", fixedSize: size)
	}
}
#endif
