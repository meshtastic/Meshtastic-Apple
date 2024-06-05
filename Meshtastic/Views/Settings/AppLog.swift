//
//  AppLog.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 6/4/24.
//

import SwiftUI
import OSLog

struct AppLog: View {
	@State private var text = "Loading..."
	
	var body: some View {
		ScrollView {
			Text(text)
				.textSelection(.enabled)
				.fontDesign(.monospaced)
				.font(.caption2)
				.padding()
		}
		.task {
			text = await fetchLogs()
		}
	}
}

extension AppLog {
  static private let template = NSPredicate(format:
  "(subsystem BEGINSWITH $PREFIX) || ((subsystem IN $SYSTEM) && ((messageType == error) || (messageType == fault)))")

  @MainActor
  private func fetchLogs() async -> String {
	let calendar = Calendar.current
	guard let dayAgo = calendar.date(byAdding: .day,
	  value: -1, to: Date.now) else {
	  return "Invalid calendar"
	}

	do {
	  let predicate = AppLog.template.withSubstitutionVariables(
		[
			"PREFIX": "gvh.MeshtasticClient",
			"SYSTEM": ["com.apple.coredata"]
		])

	  let logs = try await Logger.fetch(since: dayAgo,
		predicateFormat: predicate.predicateFormat)
	  return logs.joined()
	} catch {
	  return error.localizedDescription
	}
  }
}
