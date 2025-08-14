//
//  AppLogFilter.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 6/15/24.
//

import Foundation
import OSLog
import SwiftUI

enum LogCategories: Int, CaseIterable, Identifiable {

	case admin = 0
	case data = 1
	case mesh = 2
	case mqtt = 3
	case radio = 4
	case services = 5
	case stats = 6
	case transport = 7

	var id: Int { self.rawValue }
	var description: String {
		switch self {

		case .admin:
			return "🏛 Admin"
		case .data:
			return "🗄️ Data"
		case .mesh:
			return "🕸️ Mesh"
		case .mqtt:
			return "📱 MQTT"
		case .radio:
			return "📟 Radio"
		case .services:
			return "🍏 Services"
		case .stats:
			return "📊 Stats"
		case .transport:
			return "🚚 Transport"
		}
	}
}

enum LogLevels: Int, CaseIterable, Identifiable {

	case debug = 0
	case info = 1
	case notice = 2
	case error = 3
	case fault = 4

	var id: Int { self.rawValue }
	var level: String {
		switch self {
		case .debug:
			return  "debug"
		case .info:
			return "info"
		case .notice:
			return "notice"
		case .error:
			return "error"
		case .fault:
			return "fault"
		}
	}
	var description: String {
		switch self {
		case .debug:
			return  "🪲 Debug"
		case .info:
			return "ℹ️ Info"
		case .notice:
			return "⚠️ Notice"
		case .error:
			return "🚨 Error"
		case .fault:
			return "💥 Fault"
		}
	}
	var color: Color {
		switch self {
		case .debug:
			return .indigo
		case .info:
			return .green
		case .notice:
			return .orange
		case .error:
			return .red
		case .fault:
			return .red
		}
	}
}

struct AppLogFilter: View {

	@Environment(\.dismiss) private var dismiss
	@State private var currentDetent = PresentationDetent.medium
	/// Filters
	var filterTitle = "App Log Filters"
	@Binding var categories: Set<Int>
	@Binding var levels: Set<Int>
	@State var editMode = EditMode.active

	var body: some View {

		NavigationStack {
			Form {
				Section(header: Text("Categories")) {
					VStack {
						List(LogCategories.allCases, selection: $categories) { cat in
							Text(cat.description)
						}
						.listStyle(.plain)
						.environment(\.editMode, $editMode) /// bind it here!
						.frame(minHeight: 338, maxHeight: .infinity)
					}
				}
				Section(header: Text("Log Levels")) {
					VStack {
						List(LogLevels.allCases, selection: $levels) { level in
							Text(level.description)
								.foregroundStyle(level.color)
						}
						.listStyle(.plain)
						.environment(\.editMode, $editMode) /// bind it here!
						.frame(minHeight: 210, maxHeight: .infinity)
					}
				}
			}

#if targetEnvironment(macCatalyst)
			Spacer()
			Button {
				dismiss()
			} label: {
				Label("Close", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)
#endif
		}
		.presentationDetents([.medium, .large], selection: $currentDetent)
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .medium))
	}
}
