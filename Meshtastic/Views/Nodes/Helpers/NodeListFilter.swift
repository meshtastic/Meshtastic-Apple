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
	@Binding var viaLora: Bool
	@Binding var viaMqtt: Bool
	@Binding var isOnline: Bool
	@Binding var isFavorite: Bool
	@Binding var isEnvironment: Bool
	@Binding var distanceFilter: Bool
	@Binding var maximumDistance: Double
	@Binding var hopsAway: Double
	@Binding var roleFilter: Bool
	@Binding var deviceRoles: Set<Int>

	var body: some View {

		NavigationStack {
			Form {
				Section(header: Text(filterTitle)) {
					Toggle(isOn: $viaLora) {

						Label {
							Text("Via Lora")
						} icon: {
							Image(systemName: "dot.radiowaves.left.and.right")
								.rotationEffect(.degrees(-90))
								.symbolRenderingMode(.multicolor)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Toggle(isOn: $viaMqtt) {

						Label {
							Text("Via Mqtt")
						} icon: {
							Image(systemName: "dot.radiowaves.up.forward")
								.symbolRenderingMode(.multicolor)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $isOnline) {

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

					Toggle(isOn: $isFavorite) {

						Label {
							Text("Favorites")
						} icon: {

							Image(systemName: "star.fill")
								.symbolRenderingMode(.multicolor)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $isEnvironment) {

						Label {
							Text("Environment")
						} icon: {
							Image(systemName: "cloud.sun")
								.symbolRenderingMode(.multicolor)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $distanceFilter) {

						Label {
							Text("Distance")
						} icon: {
							Image(systemName: "map")
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					.listRowSeparator(distanceFilter ? .hidden : .visible)
					if distanceFilter {
						HStack {
							Label("Show nodes", systemImage: "lines.measurement.horizontal")
							Picker("", selection: $maximumDistance) {
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
							value: $hopsAway,
							in: -1...7,
							step: 1
						) {
							Text("Speed")
						} minimumValueLabel: {
							Text("All")
						} maximumValueLabel: {
							Text("7")
						}
						if hopsAway >= 0 {
							if hopsAway == 0 {
								Text("Direct")
							} else if hopsAway == 1 {
								Text("1 hop away")
							} else {
								Text("\(Int(hopsAway)) or less hops away")							}
						}
					}
					Toggle(isOn: $roleFilter) {

						Label {
							Text("Roles")
						} icon: {
							Image(systemName: "apps.iphone")
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					if roleFilter {
						VStack {
							List(DeviceRoles.allCases, selection: $deviceRoles) { dr in
								Label {
									Text("  \(dr.name)")
								} icon: {
									Image(systemName: dr.systemName)
								}
							}
							.listStyle(.plain)
							.environment(\.editMode, $editMode) /// bind it here!
							.frame(minHeight: 490, maxHeight: .infinity)
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
				Label("close", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)
#endif
		}
		.presentationDetents([.medium, .large])
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .medium))
	}
}
