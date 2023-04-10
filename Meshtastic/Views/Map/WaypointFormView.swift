//
//  WaypointFormView.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 1/10/23.
//

import SwiftUI
import CoreLocation

struct WaypointFormView: View {

	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var dismiss
	@State var coordinate: WaypointCoordinate
	@FocusState private var iconIsFocused: Bool
	@State private var name: String = ""
	@State private var description: String = ""
	@State private var icon: String = "📍"
	@State private var latitude: Double = 0
	@State private var longitude: Double = 0
	@State private var expires: Bool = false
	@State private var expire: Date = Date.now.addingTimeInterval(60 * 480) // 1 minute * 480 = 8 Hours
	@State private var locked: Bool = false
	@State private var lockedTo: Int64 = 0

	var body: some View {

		Form {
			let distance = CLLocation(latitude: LocationHelper.currentLocation.coordinate.latitude, longitude: LocationHelper.currentLocation.coordinate.longitude).distance(from: CLLocation(latitude: coordinate.coordinate?.latitude ?? 0, longitude: coordinate.coordinate?.longitude ?? 0))
			Section(header: Text((coordinate.waypointId > 0) ? "Editing Waypoint" : "Create Waypoint")) {
				HStack {
					Text("Location: \(String(format: "%.5f", latitude) + "," + String(format: "%.5f", longitude))")
						.textSelection(.enabled)
						.foregroundColor(Color.gray)
						.font(.caption2)
					if coordinate.coordinate?.latitude ?? 0 != 0 && coordinate.coordinate?.longitude ?? 0 != 0 {
						DistanceText(meters: distance)
							.foregroundColor(Color.gray)
							.font(.caption2)
					}
				}
				HStack {
					Text("Name")
					Spacer()
					TextField(
						"Name",
						text: $name,
						axis: .vertical
					)
					.foregroundColor(Color.gray)
					.onChange(of: name, perform: { _ in
						let totalBytes = name.utf8.count
						// Only mess with the value if it is too big
						if totalBytes > 30 {
							let firstNBytes = Data(name.utf8.prefix(30))
							if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
								// Set the name back to the last place where it was the right size
								name = maxBytesString
							}
						}
					})
				}
				HStack {
					Text("Description")
					Spacer()
					TextField(
						"Description",
						text: $description,
						axis: .vertical
					)
					.foregroundColor(Color.gray)
					.onChange(of: description, perform: { _ in
						let totalBytes = description.utf8.count
						// Only mess with the value if it is too big
						if totalBytes > 100 {
							let firstNBytes = Data(description.utf8.prefix(100))
							if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
								// Set the name back to the last place where it was the right size
								description = maxBytesString
							}
						}
					})
				}
				HStack {
					Text("Icon")
					Spacer()
					EmojiOnlyTextField(text: $icon, placeholder: "Select an emoji")
						.font(.title)
						.focused($iconIsFocused)
						.onChange(of: icon) { value in

							// If you have anything other than emojis in your string make it empty
							if !value.onlyEmojis() {
								icon = ""
							}
							// If a second emoji is entered delete the first one
							if value.count >= 1 {

								if value.count > 1 {
									let index = value.index(value.startIndex, offsetBy: 1)
									icon = String(value[index])
								}
								iconIsFocused = false
							}
						}

				}
				Toggle(isOn: $expires) {
					Label("Expires", systemImage: "clock.badge.xmark")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				if expires {
					DatePicker("Expire", selection: $expire, in: Date.now...)
						.datePickerStyle(.compact)
						.font(.callout)
				}
				Toggle(isOn: $locked) {
					Label("Locked", systemImage: "lock")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
			}
		}
		HStack {
			Button {

				var newWaypoint = Waypoint()
				// Loading a waypoint from edit
				if coordinate.waypointId > 0 {
					newWaypoint.id = UInt32(coordinate.waypointId)
					let waypoint  = getWaypoint(id: Int64(coordinate.waypointId), context: bleManager.context!)
					newWaypoint.latitudeI = waypoint.latitudeI
					newWaypoint.longitudeI = waypoint.longitudeI
				} else {
					// New waypoint
					newWaypoint.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
					newWaypoint.latitudeI = Int32(Double(coordinate.coordinate?.latitude ?? 0) * 1e7)
					newWaypoint.longitudeI = Int32(Double(coordinate.coordinate?.longitude ?? 0) * 1e7)
				}
				newWaypoint.name = name.count > 0 ? name : "Dropped Pin"
				newWaypoint.description_p = description
				// Unicode scalar value for the icon emoji string
				let unicodeScalers = icon.unicodeScalars
				// First element as an UInt32
				let unicode = unicodeScalers[unicodeScalers.startIndex].value
				newWaypoint.icon = unicode
				if locked {
					if lockedTo == 0 {
						newWaypoint.lockedTo = UInt32(bleManager.connectedPeripheral!.num)
					} else {
						newWaypoint.lockedTo = UInt32(lockedTo)
					}
				}
				if expires {
					newWaypoint.expire = UInt32(expire.timeIntervalSince1970)
				} else {
					newWaypoint.expire = 0
				}
				if bleManager.sendWaypoint(waypoint: newWaypoint) {
					dismiss()
				} else {
					dismiss()
					print("Send waypoint failed")
				}
			} label: {
				Label("Send", systemImage: "arrow.up")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.disabled(bleManager.connectedPeripheral == nil)
			.padding(.bottom)

			Button(role: .cancel) {
				dismiss()
			} label: {
				Label("cancel", systemImage: "x.circle")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)

			if coordinate.waypointId > 0 {

				Menu {
					Button("For me", action: {
						let waypoint  = getWaypoint(id: Int64(coordinate.waypointId), context: bleManager.context!)
						bleManager.context!.delete(waypoint)
					 do {
						 try bleManager.context!.save()
					 } catch {
						 bleManager.context!.rollback()
					 }
					 dismiss() })
					Button("For everyone", action: {
						var newWaypoint = Waypoint()

						if coordinate.waypointId > 0 {
							newWaypoint.id = UInt32(coordinate.waypointId)
						}
						newWaypoint.name = name.count > 0 ? name : "Dropped Pin"
						newWaypoint.description_p = description
						newWaypoint.latitudeI = Int32(coordinate.coordinate?.latitude ?? 0 * 1e7)
						newWaypoint.longitudeI = Int32(coordinate.coordinate?.longitude ?? 0 * 1e7)
						// Unicode scalar value for the icon emoji string
						let unicodeScalers = icon.unicodeScalars
						// First element as an UInt32
						let unicode = unicodeScalers[unicodeScalers.startIndex].value
						newWaypoint.icon = unicode
						if locked {
							if lockedTo == 0 {
								newWaypoint.lockedTo = UInt32(bleManager.connectedPeripheral!.num)
							} else {
								newWaypoint.lockedTo = UInt32(lockedTo)
							}
						}
						newWaypoint.expire = 1
						if bleManager.sendWaypoint(waypoint: newWaypoint) {
							dismiss()
						} else {
							dismiss()
							print("Send waypoint failed")
						}
					})
				}
				label: {
					Label("delete", systemImage: "trash")
						.foregroundColor(.red)
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding(.bottom)
			}
		}
		.onAppear {
			if coordinate.waypointId > 0 {
				let waypoint  = getWaypoint(id: Int64(coordinate.waypointId), context: bleManager.context!)
				name = waypoint.name ?? "Dropped Pin"
				description = waypoint.longDescription ?? ""
				icon = String(UnicodeScalar(Int(waypoint.icon)) ?? "📍")
				latitude = Double(waypoint.latitudeI) / 1e7
				longitude = Double(waypoint.longitudeI) / 1e7
				if waypoint.expire != nil {
					expires = true
					expire = waypoint.expire ?? Date()
				} else {
					expires = false
				}
				if waypoint.locked > 0 {
					locked = true
					lockedTo = waypoint.locked
				}
			} else {
				name = ""
				description = ""
				locked = false
				expires = false
				expire = Date.now.addingTimeInterval(60 * 480)
				icon = "📍"
				latitude = coordinate.coordinate?.latitude ?? 0
				longitude = coordinate.coordinate?.longitude ?? 0
			}
		}
	}
}
