
//
//  WaypointForm.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 1/10/23.
//

import SwiftUI
import CoreLocation

struct WaypointForm: View {

	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var dismiss
	@State var waypoint: WaypointEntity
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
		
		VStack {
			
			Text((waypoint.id > 0) ? "Editing Waypoint" : "Create Waypoint")
				.font(.largeTitle)
			Divider()
			Form {
				
				let distance = CLLocation(latitude: LocationHelper.currentLocation.latitude, longitude: LocationHelper.currentLocation.longitude).distance(from: CLLocation(latitude: waypoint.coordinate.latitude , longitude: waypoint.coordinate.longitude ))
				Section(header: Text("Coordinate") ) {
					HStack {
						Text("Location: \(String(format: "%.5f", waypoint.coordinate.latitude) + "," + String(format: "%.5f", waypoint.coordinate.longitude))")
							.textSelection(.enabled)
							.foregroundColor(Color.gray)
					}
					HStack {
						if waypoint.coordinate.latitude != 0 && waypoint.coordinate.longitude != 0 {
							DistanceText(meters: distance)
								.foregroundColor(Color.gray)
						}
					}
				}
				Section(header: Text("Waypoint Options")) {
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
					if waypoint.id  ==  0 {
						newWaypoint.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
						waypoint.id = Int64(newWaypoint.id)
					}
					newWaypoint.latitudeI = waypoint.latitudeI
					newWaypoint.longitudeI = waypoint.longitudeI
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
				.controlSize(.regular)
				.disabled(bleManager.connectedPeripheral == nil)
				.padding(.bottom)

				Button(role: .cancel) {
					dismiss()
				} label: {
					Label("cancel", systemImage: "x.circle")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.regular)
				.padding(.bottom)

				if waypoint.id > 0 {

					Menu {
						Button("For me", action: {
							bleManager.context!.delete(waypoint)
						 do {
							 try bleManager.context!.save()
						 } catch {
							 bleManager.context!.rollback()
						 }
						 dismiss() })
						Button("For everyone", action: {
							var newWaypoint = Waypoint()

							if waypoint.id > 0 {
								newWaypoint.id = UInt32(waypoint.id)
							}
							newWaypoint.name = name.count > 0 ? name : "Dropped Pin"
							newWaypoint.description_p = description
							newWaypoint.latitudeI = waypoint.longitudeI
							newWaypoint.longitudeI = waypoint.latitudeI
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
					.controlSize(.regular)
					.padding(.bottom)
				}
			}
		}
		.onAppear {
			if waypoint.id > 0 {
				let waypoint  = getWaypoint(id: Int64(waypoint.id), context: bleManager.context!)
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
				latitude = waypoint.coordinate.latitude 
				longitude = waypoint.coordinate.longitude
			}
		}
	}
}