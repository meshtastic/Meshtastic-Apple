//
//  WaypointForm.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 1/10/23.
//

import CoreLocation
import MapKit
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct WaypointForm: View {

	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var dismiss
	@State var waypoint: WaypointEntity
	let distanceFormatter = MKDistanceFormatter()
	@State var editMode: Bool = false
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
	@State private var detents: Set<PresentationDetent> = [.medium, .fraction(0.85)]
	@State private var selectedDetent: PresentationDetent = .medium

	var body: some View {
		NavigationStack {
			if editMode {
				Text((waypoint.id > 0) ? "Editing Waypoint" : "Create Waypoint")
					.font(.largeTitle)
				Divider()
				Form {
					let distance = CLLocation(latitude: LocationsHandler.currentLocation.latitude, longitude: LocationsHandler.currentLocation.longitude).distance(from: CLLocation(latitude: waypoint.coordinate.latitude, longitude: waypoint.coordinate.longitude ))
					Section(header: Text("Coordinate") ) {
						HStack {
							Text("Location:")
								.foregroundColor(.secondary)
							Text("\(String(format: "%.5f", waypoint.coordinate.latitude) + "," + String(format: "%.5f", waypoint.coordinate.longitude))")
								.textSelection(.enabled)
								.foregroundColor(.secondary)
								.font(.caption)
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
							.onChange(of: name) {
								var totalBytes = name.utf8.count
								// Only mess with the value if it is too big
								while totalBytes > 30 {
									name = String(name.dropLast())
									totalBytes = name.utf8.count
								}
							}
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
							.onChange(of: description) {
								var totalBytes = description.utf8.count
								// Only mess with the value if it is too big
								while totalBytes > 100 {
									description = String(description.dropLast())
									totalBytes = description.utf8.count
								}
							}
						}
						HStack {
							Text("Icon")
							Spacer()
							EmojiOnlyTextField(text: $icon, placeholder: "Select an emoji")
								.font(.title)
								.focused($iconIsFocused)
								.onChange(of: icon) { _, value in

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
				.scrollDismissesKeyboard(.immediately)
				HStack {
					Button {
						/// Send a new or exiting waypoint
						var newWaypoint = Waypoint()
						if waypoint.id  ==  0 {
							newWaypoint.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
							waypoint.id = Int64(newWaypoint.id)
						} else {
							newWaypoint.id = UInt32(waypoint.id)
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
							Logger.mesh.warning("Send waypoint failed")
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
						Label("Cancel", systemImage: "x.circle")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.regular)
					.padding(.bottom)

					if waypoint.id > 0 && bleManager.isConnected {

						Menu {
							Button("For me", action: {
								bleManager.context.delete(waypoint)
								do {
									try bleManager.context.save()
								} catch {
									bleManager.context.rollback()
								}
								dismiss() })
							Button("For everyone", action: {
								var newWaypoint = Waypoint()
								newWaypoint.id = UInt32(waypoint.id)
								newWaypoint.name = name.count > 0 ? name : "Dropped Pin"
								newWaypoint.description_p = description
								newWaypoint.latitudeI = waypoint.latitudeI
								newWaypoint.longitudeI = waypoint.longitudeI
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
								newWaypoint.expire = UInt32(1)
								if bleManager.sendWaypoint(waypoint: newWaypoint) {

									bleManager.context.delete(waypoint)
									do {
										try bleManager.context.save()
									} catch {
										bleManager.context.rollback()
									}
									dismiss()
								} else {
									dismiss()
									Logger.mesh.warning("Send waypoint failed")
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
			} else {
				VStack {
					HStack {
						CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 50)
						Spacer()
						Text(waypoint.name ?? "?")
							.font(.largeTitle)
						Spacer()
						if waypoint.locked > 0 {
							Image(systemName: "lock.fill" )
								.font(.largeTitle)
						} else {
							Button {
								editMode = true
								selectedDetent = .fraction(0.85)
							} label: {
								Image(systemName: "square.and.pencil" )
									.font(.largeTitle)
									.symbolRenderingMode(.hierarchical)
									.foregroundColor(.accentColor)
							}
						}
					}
					Divider()
					VStack(alignment: .leading) {
						// Description
						if (waypoint.longDescription ?? "").count > 0 {
							Label {
								Text(waypoint.longDescription ?? "")
									.foregroundColor(.primary)
									.multilineTextAlignment(.leading)
									.fixedSize(horizontal: false, vertical: true)
							} icon: {
								Image(systemName: "doc.plaintext")
							}
							.padding(.bottom)
						}
						/// Coordinate
						Label {
							Text("Coordinates:")
								.foregroundColor(.primary)
							Text("\(String(format: "%.6f", waypoint.coordinate.latitude)), \(String(format: "%.6f", waypoint.coordinate.longitude))")
								.textSelection(.enabled)
								.foregroundColor(.secondary)
								.font(.caption2)
						} icon: {
							Image(systemName: "mappin.circle")
						}
						.padding(.bottom)
						// Drop Maps Pin
						Button(action: {
							if let url = URL(string: "http://maps.apple.com/?ll=\(waypoint.coordinate.latitude),\(waypoint.coordinate.longitude)&q=\(waypoint.name ?? "Dropped Pin")") {
							   UIApplication.shared.open(url)
							}
						}) {
							Label("Drop Pin in Maps", systemImage: "mappin.and.ellipse")
						}
						.padding(.bottom)
						/// Created
						Label {
							Text("Created: \(waypoint.created?.formatted() ?? "?")")
								.foregroundColor(.primary)
						} icon: {
							Image(systemName: "clock.badge.checkmark")
								.symbolRenderingMode(.hierarchical)
						}
						.padding(.bottom)
						/// Updated
						if waypoint.lastUpdated != nil {
							Label {
								Text("Updated: \(waypoint.lastUpdated?.formatted() ?? "?")")
									.foregroundColor(.primary)
							} icon: {
								Image(systemName: "clock.arrow.circlepath")
									.symbolRenderingMode(.hierarchical)
							}
							.padding(.bottom)
						}
						/// Expires
						if waypoint.expire != nil {
							Label {
								Text("Expires: \(waypoint.expire?.formatted() ?? "?")")
									.foregroundColor(.primary)
							} icon: {
								Image(systemName: "hourglass.bottomhalf.filled")
									.symbolRenderingMode(.hierarchical)
									.frame(width: 35)
							}
							.padding(.bottom, 5)
						}
						/// Distance
						if LocationsHandler.currentLocation.distance(from: LocationsHandler.DefaultLocation) > 0.0 {
							let metersAway = waypoint.coordinate.distance(from: LocationsHandler.currentLocation)
							Label {
								Text("Distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway)))")
									.foregroundColor(.primary)
							} icon: {
								Image(systemName: "lines.measurement.horizontal")
									.symbolRenderingMode(.hierarchical)
									.frame(width: 35)
							}
							.padding(.bottom, 5)
						}
					}
					.padding(.top)
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
					.padding()
#endif
				}
			}
		}
		.onAppear {
			if waypoint.id > 0 {
				let waypoint  = getWaypoint(id: Int64(waypoint.id), context: bleManager.context)
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
		.presentationDetents(detents, selection: $selectedDetent)
		.presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.85)))
		.presentationDragIndicator(.visible)
	}
}
