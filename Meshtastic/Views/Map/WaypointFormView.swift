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
	@State var coordinate: CLLocationCoordinate2D
	@State var waypointId : Int = 0
	
	@FocusState private var iconIsFocused: Bool
	
	@State private var name: String = ""
	@State private var description: String = ""
	@State private var icon: String = "📍"
	@State private var latitude: Double = 0
	@State private var longitude: Double = 0
	@State private var expires: Bool = false
	@State private var expire: Date = Date() // = Date.now.addingTimeInterval(60 * 120) // 1 minute * 120 = 2 Hours
	@State private var locked: Bool = false
	@State private var lockedTo: Int64 = 0
	
	var body: some View {
		
		Form {
			let distance = CLLocation(latitude: LocationHelper.currentLocation.latitude, longitude: LocationHelper.currentLocation.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
			Section(header: Text((waypointId > 0) ? "Editing Waypoint" : "Create Waypoint")) {
				HStack {
					Text("Location: \(String(format: "%.5f", latitude) + "," + String(format: "%.5f", longitude))")
						.textSelection(.enabled)
						.foregroundColor(Color.gray)
						.font(.caption2)
					if coordinate.latitude != LocationHelper.DefaultLocation.latitude && coordinate.longitude != LocationHelper.DefaultLocation.longitude {
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
					.onChange(of: name, perform: { value in
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
					.onChange(of: description, perform: { value in
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
//				Toggle(isOn: $expires) {
//					Label("Expires", systemImage: "clock.badge.xmark")
//				}
//				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
//				if expires {
//					DatePicker("Expire", selection: $expire, in: Date.now...)
//						.datePickerStyle(.compact)
//						.font(.callout)
//				}
				Toggle(isOn: $locked) {
					Label("Locked", systemImage: "lock")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
			}
		}
		HStack {
			Button {
				
				var newWaypoint = Waypoint()
				
				if waypointId > 0 {
					newWaypoint.id = UInt32(waypointId)
				} else {
					newWaypoint.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
				}
				newWaypoint.name = name.count > 0 ? name : "Dropped Pin"
				newWaypoint.description_p = description
				newWaypoint.latitudeI = Int32(coordinate.latitude * 1e7)
				newWaypoint.longitudeI = Int32(coordinate.longitude * 1e7)
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
				if expire.timeIntervalSince1970 > 0 {
					newWaypoint.expire = UInt32(expire.timeIntervalSince1970)
				}
				if bleManager.sendWaypoint(waypoint: newWaypoint) {
					waypointId = 0
					dismiss()
				} else {
					waypointId = 0
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
			
			Button(role:.cancel) {
				dismiss()
			} label: {
				Label("cancel", systemImage: "x.circle")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)

			if waypointId > 0 {
				Button(role: .destructive) {
					let waypoint  = getWaypoint(id: Int64(waypointId), context: bleManager.context!)
					bleManager.context!.delete(waypoint)
					do {
						try bleManager.context!.save()
					} catch {
						bleManager.context!.rollback()
					}
					dismiss()
				} label: {
					Label("delete", systemImage: "trash")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding(.bottom)
			}
		}
		.onChange(of: waypointId) { newId in
			print(newId)
			
		}
		.onAppear {
			if waypointId > 0 {
				let waypoint  = getWaypoint(id: Int64(waypointId), context: bleManager.context!)
				waypointId = Int(waypoint.id)
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
				expire = Date.now.addingTimeInterval(60 * 120)
				icon = "📍"
				latitude = coordinate.latitude
				longitude = coordinate.longitude
			}
			
			if coordinate.distance(from: LocationHelper.DefaultLocation) == 0.0 {
				// Too close to apple park, bail out
				waypointId = 0
				dismiss()
			}
		}
	}
}
