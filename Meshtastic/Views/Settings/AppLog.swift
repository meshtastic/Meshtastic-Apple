//
//  AppLog.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 6/4/24.
//

import SwiftUI
import OSLog

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

	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	private let dateFormatStyle = Date.FormatStyle()
		.hour(.twoDigits(amPM: .omitted))
		.minute()
		.second()
		.secondFraction(.fractional(3))

	var body: some View {
		HStack {

			if idiom == .phone {
				Table(logs, selection: $selection, sortOrder: $sortOrder) {
					TableColumn("log.message", value: \.composedMessage) { value in
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
				.searchable(text: $searchText, placement: .navigationBarDrawer, prompt: "Search")
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
			} else {
				Table(logs, selection: $selection, sortOrder: $sortOrder) {
					TableColumn("log.time") { value in
						Text(value.date.formatted(dateFormatStyle))
					}
					.width(min: 125, max: 150)
					TableColumn("log.level") { value in
						Text(value.level.description)
							.foregroundStyle(value.level.color)
					}
					.width(min: 85, max: 110)
					TableColumn("log.category", value: \.category)
						.width(min: 80, max: 130)
					TableColumn("log.message", value: \.composedMessage) { value in
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
				.searchable(text: $searchText, placement: .navigationBarDrawer, prompt: "Search")
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
		}
		.onChange(of: sortOrder) { _, sortOrder in
			withAnimation {
				logs.sort(using: sortOrder)
			}
		}
		.onChange(of: searchText) { _ in
			Task {
				await logs = searchAppLogs()
				logs.sort(using: sortOrder)
			}
		}
		.onChange(of: [categories]) { _ in
			Task {
				await logs = searchAppLogs()
				logs.sort(using: sortOrder)
			}
		}
		.onChange(of: [levels]) { _ in
			Task {
				await logs = searchAppLogs()
				logs.sort(using: sortOrder)
			}
		}
		.onChange(of: selection) { newSelection in
			presentingErrorDetails = true
			let log = logs.first {
			   $0.id == newSelection
			 }
			selectedLog = log
		}
		.sheet(isPresented: $isEditingFilters) {
			AppLogFilter(categories: $categories, levels: $levels)
		}
		.sheet(item: $selectedLog, onDismiss: didDismiss) { log in
			LogDetail(log: log)
				.padding()
		}
		.task {
			logs = await searchAppLogs()
			logs.sort(using: sortOrder)
		}
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("Meshtastic Application Logs"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Application log download succeeded.")
				case .failure(let error):
					Logger.services.error("Application log download failed: \(error.localizedDescription)")
				}
			}
		)
		.navigationBarTitle("Debug Logs\(logs.isEmpty ? "" : " (\(logs.count))")", displayMode: .inline)
		.toolbar {
#if targetEnvironment(macCatalyst)
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
#endif
			if !logs.isEmpty {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button(action: {
						exportString = logToCsvFile(log: logs)
						isExporting = true
					}) {
						Image(systemName: "square.and.arrow.down")
					}
				}
			}
		}
	}
	func didDismiss() {
		selection = nil
		selectedLog = nil
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

extension OSLogEntry: Identifiable { }
