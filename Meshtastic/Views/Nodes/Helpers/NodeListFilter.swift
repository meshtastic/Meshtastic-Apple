//
//  NodeListFilter.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/25/24.
//

import Foundation
import SwiftUI
import NavigationBackport

struct NodeListFilter: View {
	@Environment(\.dismiss) private var dismiss
	@State var editMode = EditMode.active
	var filterTitle = "Node Filters"
//	@Binding var viaLora: Bool
//	@Binding var viaMqtt: Bool
//	@Binding var isOnline: Bool
//	@Binding var isPkiEncrypted: Bool
//	@Binding var isFavorite: Bool
//	@Binding var isIgnored: Bool
//	@Binding var isEnvironment: Bool
//	@Binding var distanceFilter: Bool
//	@Binding var maximumDistance: Double
//	@Binding var hopsAway: Double
//	@Binding var roleFilter: Bool
//	@Binding var deviceRoles: Set<Int>
	@ObservedObject var filters: NodeFilterParameters
	
	var body: some View {

		NBNavigationStack {
			Form {
				Section(header: Text(filterTitle)) {
					Toggle(isOn: $filters.viaLora) {

						Label {
							Text("Via Lora")
						} icon: {
							Image(systemName: "dot.radiowaves.left.and.right")
								.rotationEffect(.degrees(-90))
								.symbolRenderingMode(.multicolor)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Toggle(isOn: $filters.viaMqtt) {

						Label {
							Text("Via Mqtt")
						} icon: {
							Image(systemName: "dot.radiowaves.up.forward")
								.symbolRenderingMode(.multicolor)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $filters.isOnline) {

						Label {
							Text("Online")
						} icon: {
							Image(systemName: "checkmark.circle.fill")
								.foregroundColor(.green)
								.symbolRenderingMode(.hierarchical)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $filters.isPkiEncrypted) {

						Label {
							Text("Encrypted")
						} icon: {
							Image(systemName: "lock.fill")
								.foregroundColor(.green)
								.symbolRenderingMode(.hierarchical)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $filters.isFavorite) {

						Label {
							Text("Favorites")
						} icon: {

							Image(systemName: "star.fill")
								.symbolRenderingMode(.multicolor)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					if filterTitle == "Node Filters" {
						Toggle(isOn: $filters.isIgnored) {

							Label {
								Text("Ignored")
							} icon: {

								Image(systemName: "minus.circle.fill")
									.symbolRenderingMode(.multicolor)
							}
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.listRowSeparator(.visible)

						Toggle(isOn: $filters.isEnvironment) {
							Label {
								Text("Environment")
							} icon: {
								Image(systemName: "cloud.sun")
									.symbolRenderingMode(.multicolor)
							}
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.listRowSeparator(.visible)
					}
					Toggle(isOn: $filters.distanceFilter) {

						Label {
							Text("Distance")
						} icon: {
							Image(systemName: "map")
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					.listRowSeparator(filters.distanceFilter ? .hidden : .visible)
					if filters.distanceFilter {
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
								Text("\(Int(filters.hopsAway)) or less hops away")							}
						}
					}
					Toggle(isOn: $filters.roleFilter) {

						Label {
							Text("Roles")
						} icon: {
							Image(systemName: "apps.iphone")
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					if filters.roleFilter {
						VStack {
							List(DeviceRoles.allCases, selection: $filters.deviceRoles) { dr in
								Label {
									Text("\(dr.name)")
								} icon: {
									Image(systemName: dr.systemName)
								}
							}
							.listStyle(.plain)
							.environment(\.editMode, $editMode) /// bind it here!
							.frame(minHeight: 510, maxHeight: .infinity)
						}
					}
				}
			}
			.listStyle(.insetGrouped)
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
		.presentationDetents([.large])
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .large))
	}
}
