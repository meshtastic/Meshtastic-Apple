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
	/// Filters
	var filterTitle = "Node Filters"
	@Binding var viaLora: Bool
	@Binding var viaMqtt: Bool
	@Binding var isOnline: Bool
	@Binding var isFavorite: Bool
	@Binding var distanceFilter: Bool
	@Binding var maximumDistance: Double
	@Binding var hopsAway: Int
	@Binding var deviceRole: Int

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
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Toggle(isOn: $viaMqtt) {

						Label {
							Text("Via Mqtt")
						} icon: {
							Image(systemName: "dot.radiowaves.up.forward")
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
								.foregroundColor(.yellow)
								.symbolRenderingMode(.hierarchical)
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
					HStack {
						Label("Hops Away", systemImage: "hare")
						Picker("", selection: $hopsAway) {
							Text("Any")
								.tag(-1)
							Text("Direct")
								.tag(0)
							ForEach(1..<8) {
								Text("\($0)")
									.tag($0)
							}
						}
						.pickerStyle(DefaultPickerStyle())
					}
					HStack {
						Label("Device Role", systemImage: "apps.iphone")
						Picker("", selection: $deviceRole) {
							Text("All Roles")
								.tag(-1)
							ForEach(DeviceRoles.allCases) { dr in
								Label {
									Text("  \(dr.name)")
								} icon: {
									Image(systemName: dr.systemName)
								}
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
