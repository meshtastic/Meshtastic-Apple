//
//  AppLogFilter.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 6/15/24.
//


//
//  NodeListFilter.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/25/24.
//

import Foundation
import OSLog
import SwiftUI

enum LogCategories: Int, CaseIterable, Identifiable {

	case admin = 0
	case data = 1
	case mesh = 2
	case services = 3
	case stats = 4

	var id: Int { self.rawValue }
	var description: String {
		switch self {

		case .admin:
			return "🏛 Admin"
		case .data:
			return "🗄️ Data"
		case .mesh:
			return "🕸️ Mesh"
		case .services:
			return "🍏 Services"
		case .stats:
			return "📊 Stats"
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
			return  "🩺 Debug"
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
}

struct AppLogFilter: View {
	
	@Environment(\.dismiss) private var dismiss
	/// Filters
	var filterTitle = "App Log Filters"
	//@Binding
	@Binding var category: Int
	@Binding var level: Int
	
	var body: some View {
		
		NavigationStack {
			Form {
				Section(header: Text(filterTitle)) {
					HStack {
						Label("Category", systemImage: "square.grid.2x2")
						Picker("", selection: $category) {
							Text("All Categories")
								.tag(-1)
							ForEach(LogCategories.allCases) { lc in
									Text("\(lc.description)")
								
							}
						}
						.pickerStyle(DefaultPickerStyle())
					}
					
					HStack {
						Label("Level", systemImage: "stairs")
						Picker("", selection: $level) {
							Text("All Levels")
								.tag(-1)
							ForEach(LogLevels.allCases) { ll in
								Text("\(ll.description)")
									//.tag(ll.rawValue)
								
							}
						}
						.pickerStyle(DefaultPickerStyle())
					}
				}
			}
#if targetEnvironment(macCatalyst)
			Spacer()
			Button {
				dismiss()
			} label: {
				Label("close", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)
#endif
		}
		.presentationDetents([.fraction(0.6), .fraction(0.75)])
		.presentationDragIndicator(.visible)
	}
}
