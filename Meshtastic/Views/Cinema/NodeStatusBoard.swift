//
//  NodeStatusBoard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/29/26.
//
#if os(visionOS)
import SwiftData
import SwiftUI

/// The nodes' status messages on the cinema's second whiteboard: the connected radio's own status
/// first, then every node heard with one, latest first. Each place calls the board its own way; in
/// the ham shack it is where net control logs the check-ins. Drawn as marker on the board like the
/// team roster, landscape or portrait to suit the place. Tapping a row centers the 3D map on the
/// node and opens its details on the screen.
struct NodeStatusBoard: View {
	/// The place the board is in, for what it's called there and its shape.
	let environment: CinemaEnvironment
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Environment(\.openWindow) private var openWindow
	@State private var sheet: Sheet?

	/// The board's sizes in points. CinemaSpace scales the panel to the board in the image, so only
	/// the shape matters: 3:2 lying down, 2:3 standing.
	static let landscapeSize = CGSize(width: 1800, height: 1200)
	static let portraitSize = CGSize(width: 1200, height: 1800)
	/// How often the rows are read from the store. A few seconds late is fine on a board read from
	/// across the room, and it keeps the store work off every packet.
	private static let refreshInterval: Duration = .seconds(5)

	private var portrait: Bool { environment.statusBoardPortrait }
	private var size: CGSize { portrait ? Self.portraitSize : Self.landscapeSize }
	/// A status can run to two lines, so fewer rows than the team board; the taller board holds more.
	private var maxRows: Int { portrait ? 8 : 6 }

	var body: some View {
		// A ZStack, not a Group: the modifiers below on an empty Group attach to nothing, so the
		// task that reads the first sheet would never start.
		ZStack {
			if let sheet {
				content(sheet)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.padding(.horizontal, 56)
		.padding(.vertical, 44)
		.frame(width: size.width, height: size.height)
		.background(BoardStyle.surface)
		.environment(\.colorScheme, .light)
		.task(id: RadioKey(isConnected: accessoryManager.isConnected, num: accessoryManager.activeDeviceNum)) {
			while !Task.isCancelled {
				// The reset can start while this sleeps; don't read rows that are being deleted.
				if !appState.isDatabaseResetting {
					sheet = makeSheet()
				}
				try? await Task.sleep(for: Self.refreshInterval)
			}
		}
	}

	@ViewBuilder
	private func content(_ sheet: Sheet) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			title
			if sheet.entries.isEmpty {
				emptyState
			} else {
				if !portrait {
					headerRow
						.padding(.top, 28)
				}
				Rectangle()
					.fill(BoardStyle.ink)
					.frame(height: 5)
					.padding(.top, portrait ? 24 : 8)
				ForEach(sheet.entries) { entry in
					Button {
						show(entry.id)
					} label: {
						StatusRow(entry: entry, now: sheet.date, portrait: portrait)
					}
					.buttonStyle(.plain)
					.hoverEffect(.highlight)
				}
				Spacer(minLength: 0)
				footer(sheet)
			}
		}
	}

	// MARK: Pieces

	private var title: some View {
		HStack(alignment: .firstTextBaseline) {
			Text(verbatim: environment.statusBoardTitle)
				.textCase(.uppercase)
				.font(BoardStyle.marker(portrait ? 80 : 92))
				.foregroundStyle(BoardStyle.blue)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
			Spacer()
			MeshLogo(height: 44)
				.padding(.leading, 18)
		}
	}

	private var headerRow: some View {
		HStack(spacing: StatusRow.spacing) {
			Text("Node")
				.frame(width: StatusRow.nameWidth, alignment: .leading)
			Text("Status")
				.frame(maxWidth: .infinity, alignment: .leading)
			Text("Last heard")
				.frame(width: StatusRow.heardWidth, alignment: .leading)
		}
		.textCase(.uppercase)
		.font(BoardStyle.marker(38))
		.foregroundStyle(BoardStyle.ink)
		.lineLimit(1)
		.minimumScaleFactor(0.6)
	}

	@ViewBuilder
	private func footer(_ sheet: Sheet) -> some View {
		if sheet.hiddenCount > 0 {
			Text("+\(sheet.hiddenCount) more", comment: "Cinema team board: how many favorite nodes didn't fit on the board")
				.font(BoardStyle.marker(40))
				.foregroundStyle(BoardStyle.faded)
		} else if sheet.radioCanPost {
			Text("Set your radio's status in its node details to post it here.", comment: "Cinema status board: hint shown while the connected radio has no status message of its own")
				.font(BoardStyle.marker(40))
				.foregroundStyle(BoardStyle.faded)
		}
	}

	private var emptyState: some View {
		VStack(spacing: 24) {
			Spacer()
			Text(verbatim: environment.statusBoardEmptyTitle)
				.font(BoardStyle.marker(80))
				.foregroundStyle(BoardStyle.blue)
				.multilineTextAlignment(.center)
			Text("Nodes that broadcast a status message are listed here as they're heard.", comment: "Cinema status board: how the empty board fills")
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
	private struct Sheet {
		let date: Date
		let entries: [Entry]
		let hiddenCount: Int
		/// The connected radio could post a status and hasn't.
		let radioCanPost: Bool
	}

	/// Reads the radio's status and the nodes with one that fit on the board, most recently heard
	/// first. Only the rows shown are read in full, so the work doesn't grow with the mesh.
	private func makeSheet() -> Sheet {
		let radio = accessoryManager.isConnected ? accessoryManager.activeDeviceNum.flatMap { getNodeInfo(id: $0, context: context) } : nil
		var entries: [Entry] = []
		if let radio, let status = radio.statusMessageDisplay {
			entries.append(entry(radio, status: status, isRadio: true))
		}
		// No node has a negative number, so this matches every node when there's no radio.
		let radioNum = radio?.num ?? -1
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.nodeStatus != nil && $0.num != radioNum },
			sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
		)
		let total = (try? context.fetchCount(descriptor)) ?? 0
		let room = maxRows - entries.count
		// A status can be all invisible characters, which gets no row, so a few more are read than fit.
		descriptor.fetchLimit = room + 4
		let heard = ((try? context.fetch(descriptor)) ?? []).compactMap { node in
			node.statusMessageDisplay.map { entry(node, status: $0, isRadio: false) }
		}
		let shown = heard.prefix(room)
		entries += shown
		return Sheet(
			date: .now,
			entries: entries,
			hiddenCount: max(0, total - shown.count),
			radioCanPost: radio.map { $0.statusMessageDisplay == nil && $0.firmwareSupportsStatusMessage } ?? false
		)
	}

	private func entry(_ node: NodeInfoEntity, status: String, isRadio: Bool) -> Entry {
		let user = node.liveUser
		return Entry(
			id: node.num,
			shortName: user?.shortName ?? String(hexName(node.num).suffix(4)),
			longName: user?.longName ?? hexName(node.num),
			status: status,
			lastHeard: node.lastHeard,
			isRadio: isRadio,
			isOnline: node.isOnline
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
private struct Entry: Identifiable {
	let id: Int64
	let shortName: String
	let longName: String
	/// Free text from the mesh, shown as it came.
	let status: String
	let lastHeard: Date?
	let isRadio: Bool
	/// Heard in the last two hours.
	let isOnline: Bool
}

/// A node and its status. Lying down, the board has columns; standing, each row is the node with
/// when it was heard, and its status under that.
private struct StatusRow: View {
	let entry: Entry
	let now: Date
	let portrait: Bool

	static let spacing: CGFloat = 16
	static let nameWidth: CGFloat = 450
	static let heardWidth: CGFloat = 280

	/// Nodes not heard lately are written in the faded ink, which still reads at full contrast.
	private var ink: Color {
		entry.isRadio || entry.isOnline ? BoardStyle.ink : BoardStyle.faded
	}

	var body: some View {
		Group {
			if portrait {
				standing
			} else {
				lying
			}
		}
		.padding(.vertical, 8)
		.frame(minHeight: 104)
		.overlay(alignment: .bottom) {
			Rectangle()
				.fill(BoardStyle.ink.opacity(0.3))
				.frame(height: 3)
		}
		.contentShape(Rectangle())
		.accessibilityElement(children: .combine)
	}

	private var lying: some View {
		HStack(alignment: .top, spacing: Self.spacing) {
			HStack(spacing: 22) {
				NodeChip(shortName: entry.shortName, colorSeed: UInt32(truncatingIfNeeded: entry.id), size: 78)
				name
			}
			.frame(width: Self.nameWidth, alignment: .leading)
			status
				.padding(.top, 14)
			heard
				.frame(width: Self.heardWidth, alignment: .leading)
				.padding(.top, 16)
		}
	}

	private var standing: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 22) {
				NodeChip(shortName: entry.shortName, colorSeed: UInt32(truncatingIfNeeded: entry.id), size: 78)
				name
				Spacer(minLength: 16)
				heard
			}
			status
				.padding(.leading, 100)
		}
		.padding(.vertical, 8)
	}

	private var name: some View {
		Text(verbatim: entry.longName)
			.font(BoardStyle.marker(50))
			.foregroundStyle(entry.isRadio ? BoardStyle.blue : ink)
			.lineLimit(1)
			.minimumScaleFactor(0.6)
	}

	private var status: some View {
		Text(verbatim: entry.status)
			.font(BoardStyle.marker(46))
			.foregroundStyle(ink)
			.lineLimit(2)
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var heard: some View {
		HStack(spacing: 12) {
			if entry.isRadio {
				Image(systemName: "link")
					.font(.system(size: 32, weight: .bold))
					.accessibilityHidden(true)
				Text("Connected")
			} else {
				Image(systemName: entry.isOnline ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
					.font(.system(size: 32, weight: .bold))
					.accessibilityHidden(true)
				// Moves on with the board's refresh, not every second.
				Text(verbatim: (entry.lastHeard ?? now).formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
			}
		}
		.font(BoardStyle.marker(portrait ? 38 : 42))
		.foregroundStyle(entry.isRadio ? BoardStyle.green : entry.isOnline ? BoardStyle.ink : BoardStyle.red)
		.lineLimit(1)
		.minimumScaleFactor(0.6)
	}
}
#endif
