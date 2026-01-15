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

	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.managedObjectContext) var context
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
	@State private var waypointFailedAlert: Bool = false

	var body: some View {
		NavigationStack {
			if editMode {
				Text((waypoint.id > 0) ? "Editing Waypoint" : "Create Waypoint")
					.font(.largeTitle)
				Divider()
				Form {
					if let cl = LocationsHandler.currentLocation {
						let distance = CLLocation(latitude: cl.latitude, longitude: cl.longitude).distance(from: CLLocation(latitude: waypoint.coordinate.latitude, longitude: waypoint.coordinate.longitude ))
						Section(header: Text("Coordinate") ) {
							HStack {
								Text("Location:")
									.foregroundColor(.secondary)
								Text("\(String(format: "%.5f", waypoint.coordinate.latitude) + "," + String(format: "%.5f", waypoint.coordinate.longitude))")
									.textSelection(.enabled)
									.foregroundColor(.secondary)
									.font(.caption)
								
							}
							Button {
								waypoint.coordinate.longitude = cl.longitude
								waypoint.coordinate.latitude = cl.latitude
							} label: {
								HStack {
									Text("Use my Location")
									Image(systemName: "location")
								}
							}
							.accessibilityLabel("Set to current location")
							HStack {
								if waypoint.coordinate.latitude != 0 && waypoint.coordinate.longitude != 0 {
									DistanceText(meters: distance)
										.foregroundColor(Color.gray)
								}
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
								waypoint.name = name.count > 0 ? name : "Dropped Pin"
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
						guard let deviceNum = accessoryManager.activeDeviceNum else {
							Logger.mesh.warning("Send waypoint failed: No deviceNum")
							return
						}
						if accessoryManager.isConnected {
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
									newWaypoint.lockedTo = UInt32(deviceNum)
								} else {
									newWaypoint.lockedTo = UInt32(lockedTo)
								}
							}
							if expires {
								newWaypoint.expire = UInt32(expire.timeIntervalSince1970)
							} else {
								newWaypoint.expire = 0
							}

							Task {
								do {
									try await accessoryManager.sendWaypoint(waypoint: newWaypoint)
									dismiss()
								} catch {
									Logger.mesh.warning("Send waypoint failed: \(error)")
									Task { @MainActor in
										waypointFailedAlert = true
									}
								}
							}
						} else {
							Logger.mesh.warning("Send waypoint failed, node not connected")
						}
					} label: {
						Label("Send", systemImage: "arrow.up")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.regular)
					.disabled(!accessoryManager.isConnected)
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

					if waypoint.id > 0 && accessoryManager.isConnected {

						Menu {
							Button("For me", action: {
								context.delete(waypoint)
								do {
									try context.save()
								} catch {
									context.rollback()
								}
								dismiss() })
							Button("For everyone", action: {
								guard let deviceNum = accessoryManager.activeDeviceNum else {
									Logger.mesh.error("Unable to set waypoint: No Device num")
									return
								}
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
										newWaypoint.lockedTo = UInt32(deviceNum)
									} else {
										newWaypoint.lockedTo = UInt32(lockedTo)
									}
								}
								newWaypoint.expire = UInt32(1)
								Task {
									do {
										try await accessoryManager.sendWaypoint(waypoint: newWaypoint)
										Task { @MainActor in
											context.delete(waypoint)
											do {
												try context.save()
											} catch {
												context.rollback()
											}
											dismiss()
										}
									} catch {
										Logger.mesh.warning("Send waypoint failed")
										Task {@MainActor in
											waypointFailedAlert = true
										}
									}
								}
							})
						}
					label: {
						Label("Delete", systemImage: "trash")
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
						if waypoint.locked > 0 && waypoint.locked != UInt32(accessoryManager.activeDeviceNum ?? 0) {
							Image(systemName: "lock.fill")
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
						if let cl = LocationsHandler.currentLocation {
							if cl.distance(from: cl) > 0.0 {
								let metersAway = waypoint.coordinate.distance(from: cl)
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
		.alert("Waypoint Failed to Send", isPresented: $waypointFailedAlert) {
					Button("OK", role: .cancel) {
						context.delete(waypoint)
						do {
							try context.save()
						} catch {
							context.rollback()
						}
						dismiss()
					}
				}
		.onDisappear {
			if waypoint.id == 0 {
					// New, unsent waypoint created by the user: delete it
					context.delete(waypoint)
					do {
						try context.save()
					} catch {
						context.rollback()
						Logger.mesh.error("Failed to save context on waypoint deletion: \(error)")
					}
				}
		}
		.onAppear {
			if waypoint.id > 0 {
				let waypoint  = getWaypoint(id: Int64(waypoint.id), context: context)
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
