//
//  NodeListFilter.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/25/24.
//

import Foundation
import SwiftUI

struct NodeListFilter: View {
	@Environment(\.dismiss) private var dismiss
	@State var editMode = EditMode.active
	var filterTitle = "Node Filters"
	@ObservedObject var filters: NodeFilterParameters

	var body: some View {
		NavigationStack {
			Form {
				Section {
					Toggle(isOn: $filters.viaLora) {
						Label("Via Lora", systemImage: "dot.radiowaves.left.and.right")
					}
					.labelStyle(.titleAndIcon)
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Toggle(isOn: $filters.viaMqtt) {
						Label("Via Mqtt", systemImage: "dot.radiowaves.up.forward")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $filters.isOnline) {
						Label("Online", systemImage: "checkmark.circle.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $filters.isPkiEncrypted) {
						Label("Encrypted", systemImage: "lock.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $filters.isFavorite) {
						Label("Favorites", systemImage: "star.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					if filterTitle == "Node Filters" {
						Toggle(isOn: $filters.isIgnored) {
							Label("Ignored", systemImage: "minus.circle.fill")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.listRowSeparator(.visible)

						Toggle(isOn: $filters.isEnvironment) {
							Label("Environment", systemImage: "cloud.sun")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.listRowSeparator(.visible)
					}

					Toggle(isOn: $filters.distanceFilter) {
						Label("Distance", systemImage: "map")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.disabled(LocationsHandler.currentLocation == nil && filters.fallbackLocation == nil)
					.listRowSeparator(filters.distanceFilter ? .hidden : .visible)

					if filters.distanceFilter {
						if LocationsHandler.currentLocation == nil && filters.fallbackLocation == nil {
							Text("Requires a precise GPS fix from your phone")
								.font(.caption)
								.foregroundStyle(.secondary)
						} else {
							if LocationsHandler.currentLocation == nil {
								Text("Using your connected device's position")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							HStack {
								Label("Show nodes", systemImage: "lines.measurement.horizontal")
								Picker("", selection: $filters.maxDistance) {
									ForEach(MeshMapDistances.allCases) { di in
										Text(di.description)
											.tag(di.id)
									}
								}
								.pickerStyle(DefaultPickerStyle())
							}
						}
					}

					VStack(alignment: .leading) {
						Label("Hops Away", systemImage: "hare")
						Slider(
							value: $filters.hopsAway,
							in: -1...7,
							step: 1
						) {
							Text("Speed")
						} minimumValueLabel: {
							Text("All")
						} maximumValueLabel: {
							Text("7")
						}

						if filters.hopsAway >= 0 {
							if filters.hopsAway == 0 {
								Text("Direct")
							} else if filters.hopsAway == 1 {
								Text("1 hop away")
							} else {
								Text("\(Int(filters.hopsAway)) or less hops away")
							}
						}
					}

					Toggle(isOn: $filters.roleFilter) {
						Label("Roles", systemImage: "apps.iphone")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					if filters.roleFilter {
						VStack {
							List(DeviceRoles.allCases, selection: $filters.deviceRoles) { dr in
								Label {
									Text(dr.name)
								} icon: {
									Image(systemName: dr.systemName)
								}
							}
							.listStyle(.plain)
							.environment(\.editMode, $editMode)
							.frame(minHeight: 510, maxHeight: .infinity)
						}
					}
				}
			}
			.listStyle(.insetGrouped)
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
			.buttonStyle(.plain)
			.padding(.top, 12)
			.padding(.leading, 14)
		}
		#endif
		.presentationDetents([.large])
		.presentationContentInteraction(.scrolls)
		#if !targetEnvironment(macCatalyst)
		.presentationDragIndicator(.visible)
		#endif
		.presentationBackgroundInteraction(.enabled(upThrough: .large))
	}
}

#Preview {
	NodeListFilter(filters: NodeFilterParameters())
}
