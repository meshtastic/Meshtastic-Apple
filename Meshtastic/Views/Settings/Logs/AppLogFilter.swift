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

	var color: Color {
		switch self {
		case .admin:
			return .brown
		case .data:
			return .indigo
		case .mesh:
			return .green
		case .mqtt:
			return .blue
		case .radio:
			return .orange
		case .services:
			return .mint
		case .stats:
			return .purple
		case .transport:
			return .teal
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
			return "debug"
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
			return "🪲 Debug"
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
	@Binding var isPacketStreamOn: Bool
	@Binding var categoriesExpanded: Bool
	@Binding var levelsExpanded: Bool

	var body: some View {
		NavigationStack {
			Form {
				Section {
					Toggle(isOn: $isPacketStreamOn) {
						HStack {
							Label("Packet Stream", systemImage: "dot.radiowaves.left.and.right")
								.foregroundStyle(LogCategories.mesh.color)
							if isPacketStreamOn {
								Text("LIVE")
									.font(.caption2.bold())
									.padding(.horizontal, 6)
									.padding(.vertical, 2)
									.background(LogCategories.mesh.color.opacity(0.2), in: Capsule())
									.foregroundStyle(LogCategories.mesh.color)
								Spacer()
							}
						}
					}
				} footer: {
					Text("Live view of mesh packets crossing the network. Overrides the category and level filters below.")
				}

				Section {
					collapsibleSectionHeader(title: "Categories", isExpanded: $categoriesExpanded) {
						categories.formUnion(LogCategories.allCases.map(\.id))
					}
					if categoriesExpanded {
						ForEach(LogCategories.allCases) { category in
							selectionRow(
								title: category.description,
								color: category.color,
								isSelected: categories.contains(category.id)
							) {
								toggleCategory(category.id)
							}
						}
					}
				}
				.disabled(isPacketStreamOn)

				Section {
					collapsibleSectionHeader(title: "Log Levels", isExpanded: $levelsExpanded) {
						levels.formUnion(LogLevels.allCases.map(\.id))
					}
					if levelsExpanded {
						ForEach(LogLevels.allCases) { level in
							selectionRow(
								title: level.description,
								color: level.color,
								isSelected: levels.contains(level.id)
							) {
								toggleLevel(level.id)
							}
						}
					}
				}
				.disabled(isPacketStreamOn)
			}
			.navigationTitle(filterTitle)
			.navigationBarTitleDisplayMode(.inline)
		}

		#if targetEnvironment(macCatalyst)
		.overlay(alignment: .topLeading) {
			Button {
				dismiss()
			} label: {
				Image(systemName: "xmark.circle.fill")
					.font(.system(size: 34))
					.symbolRenderingMode(.palette)
					.foregroundStyle(.white, Color(.systemGray3))
			}
			.accessibilityLabel(String(localized: "Close", comment: "VoiceOver: dismiss this sheet"))
			.buttonStyle(.plain)
			.padding(.top, 12)
			.padding(.leading, 14)
		}
		#endif
		.presentationDetents([.large], selection: $currentDetent)
		.presentationContentInteraction(.scrolls)
		#if !targetEnvironment(macCatalyst)
		.presentationDragIndicator(.visible)
		#endif
		.presentationBackgroundInteraction(.enabled(upThrough: .medium))
	}

	private func collapsibleSectionHeader(
		title: String,
		isExpanded: Binding<Bool>,
		allAction: @escaping () -> Void
	) -> some View {
		HStack {
			Button {
				withAnimation { isExpanded.wrappedValue.toggle() }
			} label: {
				HStack(spacing: 6) {
					Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					Text(title)
						.font(.headline)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			Spacer()
			Button("All", action: allAction)
				.buttonStyle(.borderless)
		}
	}

	private func selectionRow(
		title: String,
		color: Color,
		isSelected: Bool,
		action: @escaping () -> Void
	) -> some View {
		Button(action: action) {
			HStack(spacing: 12) {
				Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
				Text(title)
					.foregroundStyle(color)
				Spacer()
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}

	private func toggleCategory(_ id: Int) {
		if categories.contains(id) {
			categories.remove(id)
		} else {
			categories.insert(id)
		}
	}

	private func toggleLevel(_ id: Int) {
		if levels.contains(id) {
			levels.remove(id)
		} else {
			levels.insert(id)
		}
	}
}

#Preview {
	AppLogFilter(
		categories: .constant(Set<Int>()),
		levels: .constant(Set<Int>()),
		isPacketStreamOn: .constant(false),
		categoriesExpanded: .constant(true),
		levelsExpanded: .constant(true)
	)
}
