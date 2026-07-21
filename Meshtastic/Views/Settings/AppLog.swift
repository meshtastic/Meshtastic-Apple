//
//  AppLog.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 6/4/24.
//

import SwiftUI
@preconcurrency import OSLog

struct AppLog: View {

	@State private var logs: [OSLogEntryLog] = []
	@State private var sortOrder = [KeyPathComparator(\OSLogEntryLog.date, order: .reverse)]
	@State private var selection: OSLogEntry.ID?

	@State private var selectedLog: OSLogEntryLog?
	@State private var presentingErrorDetails: Bool = false
	@State private var searchText = ""
	@State private var categories: Set<Int> = []
	@State private var levels: Set<Int> =  []
	@State var isExporting = false
	@State var exportString = ""
	@State var isEditingFilters = false
	@State private var isPacketStreamOn = false
	@State private var categoriesExpanded = false
	@State private var levelsExpanded = false
	/// Throttles the stream's auto-scroll-to-bottom — resolving the bottom anchor of a large
	/// LazyVStack is expensive, so cap it to a few times/sec instead of every new entry.
	@State private var lastStreamScroll = Date.distantPast
	@StateObject private var streamModel = PacketStreamModel()
	@Environment(\.scenePhase) private var scenePhase

	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	/// Fixed ISO 8601-style timestamp in local time, e.g. "2026-05-29 09:37:16.305".
	/// `en_US_POSIX` keeps the format literal and locale-independent so log lines stay
	/// sortable and unambiguous regardless of device region.
	private static let logDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
		formatter.timeZone = .current
		return formatter
	}()

	var body: some View {
		Group {
		if isPacketStreamOn {
			packetStreamView
		} else {
			mainLogView
		}
		}
		.onChange(of: sortOrder) { _, sortOrder in
			withAnimation {
				logs.sort(using: sortOrder)
			}
		}
		.onChange(of: searchText) {
			Task {
				await logs = searchAppLogs()
				logs.sort(using: sortOrder)
			}
		}
		.onChange(of: [categories]) {
			Task {
				await logs = searchAppLogs()
				logs.sort(using: sortOrder)
			}
		}
		.onChange(of: [levels]) {
			Task {
				await logs = searchAppLogs()
				logs.sort(using: sortOrder)
			}
		}
		.onChange(of: selection) { _, newSelection in
			presentingErrorDetails = true
			let log = logs.first {
			   $0.id == newSelection
			 }
			selectedLog = log
		}
		.sheet(isPresented: $isEditingFilters) {
			AppLogFilter(
				categories: $categories,
				levels: $levels,
				isPacketStreamOn: $isPacketStreamOn,
				categoriesExpanded: $categoriesExpanded,
				levelsExpanded: $levelsExpanded
			)
		}
		.sheet(item: $selectedLog, onDismiss: didDismiss) { log in
			LogDetail(log: log)
				.padding()
		}
		.task {
			logs = await searchAppLogs()
			logs.sort(using: sortOrder)
		}
		.onAppear { updateStreamingState() }
		.onDisappear { streamModel.stop() }
		.onChange(of: isPacketStreamOn) { _, _ in
			// Keep accumulated stream entries when toggling in/out of stream mode;
			// the model resumes from its last-seen cursor rather than clearing.
			updateStreamingState()
		}
		.onChange(of: scenePhase) { _, _ in updateStreamingState() }
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("Meshtastic Application Logs \(Date.now.exportTimestamp)"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Application log download succeeded.")
				case .failure(let error):
					Logger.services.error("Application log download failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		)
		.searchable(text: $searchText, placement: .navigationBarDrawer, prompt: "Search")
		.navigationBarTitle(navTitle, displayMode: .inline)
		.toolbar {
#if targetEnvironment(macCatalyst)
			if !isPacketStreamOn {
				ToolbarItem(placement: .topBarLeading) {
					Button(action: {
						Task {
							await logs = searchAppLogs()
							logs.sort(using: sortOrder)
						}
					}) {
						Image(systemName: "arrow.clockwise.circle")
					}
				}
			}
#endif
			if !logs.isEmpty || (isPacketStreamOn && !streamModel.visibleEntries.isEmpty) {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button(action: {
						if isPacketStreamOn {
							Task {
								let meshLogs = await streamModel.fetchAllForExport()
								exportString = logToCsvFile(log: meshLogs)
								isExporting = true
							}
						} else {
							exportString = logToCsvFile(log: logs)
							isExporting = true
						}
					}) {
						Image(systemName: "square.and.arrow.down")
					}
				}
			}
		}
	}
	private var mainLogView: some View {
		HStack {

			if idiom == .phone {
				phoneLogTable
			} else {
				desktopLogTable
			}
		}
	}

	private var phoneLogTable: some View {
				Table(logs, selection: $selection, sortOrder: $sortOrder) {
					TableColumn("Message", value: \.composedMessage) { value in
						Text(value.composedMessage)
							.foregroundStyle(value.level.color)
							.font(.caption)
					}
					.width(ideal: 200, max: .infinity)
				}
				.monospaced()
				.safeAreaInset(edge: .bottom, alignment: .trailing) {
					HStack {
						Button(action: {
							withAnimation {
								isEditingFilters = !isEditingFilters
							}
						}) {
							Image(systemName: !isEditingFilters ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
								.padding(.vertical, 5)
						}
						.tint(Color(UIColor.secondarySystemBackground))
						.foregroundColor(.accentColor)
						.buttonStyle(.borderedProminent)
					}
					.controlSize(.regular)
					.padding(5)
				}
				.padding(.bottom, 5)
				.padding(.trailing, 5)
				.disabled(selection != nil)
				.overlay {
					if logs.isEmpty {
						ContentUnavailableView("Loading Logs. . .", systemImage: "scroll")
					}
				}
				.refreshable {
					await logs = searchAppLogs()
					logs.sort(using: sortOrder)
				}
	}

	private var desktopLogTable: some View {
				Table(logs, selection: $selection, sortOrder: $sortOrder) {
					TableColumn("Time") { value in
						Text(Self.logDateFormatter.string(from: value.date))
					}
					.width(min: 215, max: 240)
					TableColumn("Level") { value in
						Text(value.level.description)
							.foregroundStyle(value.level.color)
					}
					.width(min: 85, max: 110)
					TableColumn("Category", value: \.category)
						.width(min: 80, max: 130)
					TableColumn("Message", value: \.composedMessage) { value in
						Text(value.composedMessage)
							.foregroundStyle(value.level.color)
							.font(.body)
					}
					.width(ideal: 200, max: .infinity)
				}
				.monospaced()
				.safeAreaInset(edge: .bottom, alignment: .trailing) {
					HStack {
						Button(action: {
							withAnimation {
								isEditingFilters = !isEditingFilters
							}
						}) {
							Image(systemName: !isEditingFilters ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
								.padding(.vertical, 5)
						}
						.tint(Color(UIColor.secondarySystemBackground))
						.foregroundColor(.accentColor)
						.buttonStyle(.borderedProminent)
					}
					.controlSize(.regular)
					.padding(5)
				}
				.padding(.bottom, 5)
				.padding(.trailing, 5)
				.disabled(selection != nil)
				.overlay {
					if logs.isEmpty {
						ContentUnavailableView("Loading Logs. . .", systemImage: "scroll")
					}
				}
				.refreshable {
					await logs = searchAppLogs()
					logs.sort(using: sortOrder)
				}
	}

	func didDismiss() {
		selection = nil
		selectedLog = nil
	}

	private var navTitle: String {
		if isPacketStreamOn {
			let count = streamModel.visibleEntries.count
			return count == 0 ? "Packet Stream" : "Packet Stream (\(count))"
		} else {
			return logs.isEmpty ? "Debug Logs" : "Debug Logs (\(logs.count))"
		}
	}

	private func updateStreamingState() {
		if isPacketStreamOn && scenePhase == .active {
			streamModel.start()
		} else {
			streamModel.stop()
		}
	}

	/// One streamed log row. Phone uses the compact composed-message row (matching the
	/// phone Table); iPad/macCatalyst mirror the Mac log Table's Time/Level/Category/Message
	/// columns so the streaming view matches the existing desktop log layout.
	@ViewBuilder
	private func streamRow(_ value: OSLogEntryLog) -> some View {
		if idiom == .phone {
			Text(value.composedMessage)
				.foregroundStyle(value.level.color)
				.font(.caption)
				.frame(maxWidth: .infinity, alignment: .leading)
		} else {
			// Packet Stream is always level=Info, category=Mesh, so those columns add no
			// information — show just the timestamp and the message.
			HStack(alignment: .top, spacing: 12) {
				Text(Self.logDateFormatter.string(from: value.date))
					.lineLimit(1)
					.fixedSize(horizontal: true, vertical: false)
					.frame(width: 240, alignment: .leading)
				Text(value.composedMessage)
					.foregroundStyle(value.level.color)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.font(.body)
		}
	}

	/// Live packet stream view, used for both phone and iPad/macCatalyst. The surrounding
	/// scroll/auto-scroll/pause/empty infrastructure is shared; only the row layout differs
	/// per idiom (see `streamRow`).
	private var packetStreamView: some View {
		let entries = searchText.isEmpty
			? streamModel.visibleEntries
			: streamModel.visibleEntries.filter { $0.composedMessage.localizedCaseInsensitiveContains(searchText) }
		return ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 2) {
					ForEach(entries, id: \.id) { value in
						streamRow(value)
							.contentShape(Rectangle())
							.onTapGesture { selectedLog = value }
							.accessibilityElement(children: .combine)
							.accessibilityLabel(value.composedMessage)
							.accessibilityValue(Self.logDateFormatter.string(from: value.date))
							.accessibilityAddTraits(.isButton)
							.accessibilityAction {
								selectedLog = value
							}
					}
					Color.clear
						.frame(height: 1)
						.id("streamBottom")
				}
				.padding(.horizontal, 8)
			}
			.monospaced()
			.scrollDismissesKeyboard(.immediately)
			.overlay {
				if entries.isEmpty {
					ContentUnavailableView("Waiting for packets…", systemImage: "dot.radiowaves.left.and.right")
				}
			}
			.safeAreaInset(edge: .bottom, alignment: .trailing) {
				HStack {
					if !streamModel.isPinnedToLiveEdge {
						Button {
							streamModel.setPinned(true)
							withAnimation { proxy.scrollTo("streamBottom", anchor: .bottom) }
						} label: {
							Label("Live", systemImage: "arrow.down.to.line")
								.padding(.vertical, 5)
						}
						.buttonStyle(.borderedProminent)
					}
					// Filter button — also the way back to turn Packet Stream off.
					Button {
						withAnimation { isEditingFilters.toggle() }
					} label: {
						Image(systemName: !isEditingFilters ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
							.padding(.vertical, 5)
					}
					.tint(Color(UIColor.secondarySystemBackground))
					.foregroundColor(.accentColor)
					.buttonStyle(.borderedProminent)
				}
				.controlSize(.regular)
				.padding(5)
			}
			.gesture(
				DragGesture().onChanged { value in
					if value.translation.height > 12 { streamModel.setPinned(false) }
				}
			)
			.onChange(of: streamModel.visibleEntries.count) {
				guard streamModel.isPinnedToLiveEdge else { return }
				// Throttle: scroll-to-bottom over a large lazy stack is a costly layout pass;
				// at firehose rates doing it per-entry pegs the main actor (and starves the
				// TCP reader). A few/sec keeps it visually pinned without the churn.
				let now = Date()
				guard now.timeIntervalSince(lastStreamScroll) >= 0.3 else { return }
				lastStreamScroll = now
				proxy.scrollTo("streamBottom", anchor: .bottom)
			}
		}
	}
}

extension AppLog {
	@MainActor
	private func searchAppLogs() async -> [OSLogEntryLog] {
		do {
			/// Case Insensitive Search Text Predicates
			let searchPredicates = ["composedMessage", "category", "subsystem", "process"].map { property in
				return NSPredicate(format: "%K CONTAINS[c] %@", property, searchText)
			}
			/// Create a compound predicate using each text search preicate as an OR
			let textSearchPredicate = NSCompoundPredicate(type: .or, subpredicates: searchPredicates)
			/// Create an array of predicates to hold our AND predicates
			var predicates: [NSPredicate] = []
			/// Subsystem Predicate
			let subsystemPredicate = NSPredicate(format: "subsystem IN %@", ["com.apple.SwiftUI", "com.apple.coredata", "gvh.MeshtasticClient"])
			predicates.append(subsystemPredicate)
			/// Categories
			if categories.count > 0 {
				var categoriesArray: [NSPredicate] = []
				for c in categories {
					let categoriesPredicate = NSPredicate(format: "category == %@", LogCategories(rawValue: c)?.description ?? "services")
					categoriesArray.append(categoriesPredicate)
				}
				let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: categoriesArray)
				predicates.append(compoundPredicate)
			}
			/// Log Levels
			if levels.count > 0 {
				var levelsArray: [NSPredicate] = []
				for l in levels {
					let levelsPredicate = NSPredicate(format: "messageType == %@", LogLevels(rawValue: l)?.level ?? "info")
					levelsArray.append(levelsPredicate)
				}
				let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: levelsArray)
				predicates.append(compoundPredicate)
			}
			if predicates.count > 0 || !searchText.isEmpty {
				if !searchText.isEmpty {
					let filterPredicates = NSCompoundPredicate(type: .and, subpredicates: predicates)
					let compoundPredicate = NSCompoundPredicate(type: .and, subpredicates: [textSearchPredicate, filterPredicates])
					let logs = try await Logger.fetch(predicateFormat: compoundPredicate.predicateFormat)
					return logs
				} else {
					let filterPredicates = NSCompoundPredicate(type: .and, subpredicates: predicates)
					let logs = try await Logger.fetch(predicateFormat: filterPredicates.predicateFormat)
					return logs
				}
			} else {
				let logs = try await Logger.fetch(predicateFormat: subsystemPredicate.predicateFormat)
				return logs
			}
		} catch {
			return []
		}
	}
}

extension OSLogEntry: @retroactive Identifiable { }

#Preview {
	AppLog()
}
