//
//  AppLog.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 6/4/24.
//

import SwiftUI
import OSLog

@available(iOS 17.4, *)
struct AppLog: View {

	@State private var logs: [OSLogEntryLog] = []
	@State private var sortOrder = [KeyPathComparator(\OSLogEntryLog.date)]
	@State private var selection = Set<OSLogEntryLog.ID>()
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	var body: some View {

		Table(logs, selection: $selection, sortOrder: $sortOrder) {
			if idiom != .phone {
				TableColumn("Date", value: \.date) { value in
					Text("\(value.date, format: .dateTime)")
				}
				.width(min: 150, max: 200)
				TableColumn("Category", value: \.category)
					.width(min: 100, max: 125)
			}
			TableColumn("Message", value: \.composedMessage)
				.width(ideal: 200, max: .infinity)
		}
		.onChange(of: sortOrder) { _, sortOrder in
			logs.sort(using: sortOrder)
		}
		.task {
			logs = await fetchLogs()
		}
		.presentationCompactAdaptation(.fullScreenCover)
		.navigationTitle("Debug Logs")
	}
}

@available(iOS 17.4, *)
extension AppLog {
	static private let template = NSPredicate(format: "(subsystem BEGINSWITH $PREFIX) || ((subsystem IN $SYSTEM) && ((messageType == error) || (messageType == fault)))")

	@MainActor
	private func fetchLogs() async -> [OSLogEntryLog] {
		let calendar = Calendar.current
		guard let dayAgo = calendar.date(byAdding: .day, value: -1, to: Date.now) else {
			return []
		}
		do {
			let predicate = AppLog.template.withSubstitutionVariables(
				[
					"PREFIX": "gvh.MeshtasticClient",
					"SYSTEM": ["com.apple.coredata"]
				])
			let logs = try await Logger.fetch(since: dayAgo, predicateFormat: predicate.predicateFormat)
			return logs
		} catch {
			return []
		}
	}
}

extension OSLogEntry: Identifiable { }
