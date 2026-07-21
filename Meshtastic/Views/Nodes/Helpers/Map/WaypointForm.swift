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
@preconcurrency import SwiftData

struct WaypointForm: View {

	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
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
	@State private var geofenceRadius: Double = 0 // meters; 0 = no circular geofence
	@State private var notifyOnEnter: Bool = false
	@State private var notifyOnExit: Bool = false
	@State private var notifyFavoritesOnly: Bool = false
	@State private var geofenceBounds: GeoBounds?
	@State private var showingBoundsSelector: Bool = false
	@State private var selectedDetent: PresentationDetent = .medium
	@State private var waypointFailedAlert: Bool = false
	@State private var createdByNode: NodeInfoEntity?
	@State private var lastUpdatedByNode: NodeInfoEntity?

	var body: some View {
		NavigationStack {
		Group {
		if editMode {
			Form {
				if let cl = LocationsHandler.currentLocation {
					let distance = CLLocation(latitude: cl.latitude, longitude: cl.longitude).distance(from: CLLocation(latitude: waypoint.mapCoordinate.latitude, longitude: waypoint.mapCoordinate.longitude ))
					Section(header: Text("Coordinate") ) {
						HStack {
							Text("Location:")
								.foregroundColor(.secondary)
							Text("\(String(format: "%.5f", waypoint.mapCoordinate.latitude) + "," + String(format: "%.5f", waypoint.mapCoordinate.longitude))")
								.textSelection(.enabled)
								.foregroundColor(.secondary)
								.font(.caption)
							
						}
						Button {
							waypoint.longitudeI = Int32(cl.longitude * 1e7)
							waypoint.latitudeI = Int32(cl.latitude * 1e7)
						} label: {
							HStack {
								Text("Use my Location")
								Image(systemName: "location")
							}
						}
						.accessibilityLabel(String(localized: "Set to current location", comment: "VoiceOver label for the use-my-location button"))
						HStack {
							if waypoint.mapCoordinate.latitude != 0 && waypoint.mapCoordinate.longitude != 0 {
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
						TextField("Select an emoji", text: $icon)
							.keyboardType(.emoji)
							.font(.system(size: 34))
							.focused($iconIsFocused)
							.onChange(of: icon) { _, value in
								// If a second emoji is entered delete the first one
								if value.count >= 1 {
									if value.count > 1 {
										let index = value.index(value.startIndex, offsetBy: 1)
										icon = String(value[index])
									}
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
				Section(header: Text("Geofence")) {
					Picker(selection: $geofenceRadius) {
						Text("Off").tag(0.0)
						ForEach(GeofenceRadius.allCases) { option in
							Text(option.description).tag(option.rawValue.rounded())
						}
					} label: {
						Label("Radius", systemImage: "circle.dashed")
					}
					if geofenceBounds == nil {
						Button {
							showingBoundsSelector = true
						} label: {
							Label("Set Bounding Box", systemImage: "rectangle.dashed")
						}
					} else {
						Button {
							showingBoundsSelector = true
						} label: {
							Label("Edit Bounding Box", systemImage: "rectangle.dashed")
						}
						Button(role: .destructive) {
							geofenceBounds = nil
						} label: {
							Label("Remove Bounding Box", systemImage: "trash")
						}
					}
					if geofenceRadius > 0 || geofenceBounds != nil {
						Toggle(isOn: $notifyOnEnter) {
							Label("Notify on Enter", systemImage: "bell")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						Toggle(isOn: $notifyOnExit) {
							Label("Notify on Exit", systemImage: "bell.slash")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						if notifyOnEnter || notifyOnExit {
							Toggle(isOn: $notifyFavoritesOnly) {
								Label("Favorites Only", systemImage: "star")
							}
							.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						}
					}
				}
			}
			.scrollContentBackground(.hidden)
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
							waypoint.createdBy = Int64(deviceNum)
							waypoint.id = Int64(newWaypoint.id)
						} else {
							waypoint.lastUpdatedBy = Int64(deviceNum)
							newWaypoint.id = UInt32(waypoint.id)
						}
						newWaypoint.latitudeI = waypoint.latitudeI
						newWaypoint.longitudeI = waypoint.longitudeI
						newWaypoint.name = name.count > 0 ? name : "Dropped Pin"
						newWaypoint.description_p = description
						let unicodeScalers = icon.unicodeScalars
						let unicode = unicodeScalers.first?.value ?? 128205
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
						applyGeofence(to: &newWaypoint)
						
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
							applyGeofence(to: &newWaypoint)
							Task {
								do {
									try await accessoryManager.sendWaypoint(waypoint: newWaypoint)
									Task { @MainActor in
										context.delete(waypoint)
										do {
											try context.save()
										} catch {
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
			.navigationTitle((waypoint.id > 0) ? "Editing Waypoint" : "Create Waypoint")
			.navigationBarTitleDisplayMode(.inline)
			// end Form
		} else {
			List {
				Section {
					if let created = createdByNode {
						HStack(spacing: 8) {
							CircleText(
								text: created.user?.shortName ?? "?",
								color: Color(UIColor(hex: UInt32(created.user?.num ?? 0x808080)))
							)
							VStack(alignment: .leading) {
								Text("Created by")
									.font(.caption)
									.foregroundStyle(.secondary)
								Text(created.user?.longName ?? "Unknown")
									.font(.body)
							}
						}
					}

					if let updated = lastUpdatedByNode {
						HStack(spacing: 8) {
							CircleText(
								text: updated.user?.shortName ?? "?",
								color: Color(UIColor(hex: UInt32(updated.user?.num ?? 0x808080)))
							)
							VStack(alignment: .leading) {
								Text("Last updated by")
									.font(.caption)
									.foregroundStyle(.secondary)
								Text(updated.user?.longName ?? "Unknown")
									.font(.body)
							}
						}
					}

					if (waypoint.longDescription ?? "").count > 0 {
						Label {
							Text(waypoint.longDescription ?? "")
								.foregroundColor(.primary)
								.textSelection(.enabled)
						} icon: {
							Image(systemName: "doc.plaintext")
						}
					}
				} header: {
					HStack {
						CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 36)
						Text(waypoint.name ?? "Waypoint")
							.font(.headline)
					}
				}

				Section {
					Label {
						Text("\(String(format: "%.6f", waypoint.mapCoordinate.latitude)), \(String(format: "%.6f", waypoint.mapCoordinate.longitude))")
							.textSelection(.enabled)
							.foregroundColor(.secondary)
					} icon: {
						Image(systemName: "mappin.circle")
					}

					if let cl = LocationsHandler.currentLocation {
						let metersAway = waypoint.mapCoordinate.distance(from: cl)
						if metersAway > 0.0 {
							Label {
								Text(distanceFormatter.string(fromDistance: Double(metersAway)))
							} icon: {
								Image(systemName: "lines.measurement.horizontal")
									.symbolRenderingMode(.hierarchical)
							}
						}
					}

					Button {
						if let url = URL(string: "http://maps.apple.com/?ll=\(waypoint.mapCoordinate.latitude),\(waypoint.mapCoordinate.longitude)&q=\(waypoint.name ?? "Dropped Pin")") {
							UIApplication.shared.open(url)
						}
					} label: {
						Label("Open in Maps", systemImage: "mappin.and.ellipse")
					}
				} header: {
					Text("Location")
				}

				Section {
					Label {
						Text(waypoint.created?.formatted(date: .numeric, time: .shortened) ?? "?")
							.foregroundStyle(.secondary)
					} icon: {
						Image(systemName: "clock.badge.checkmark")
							.symbolRenderingMode(.hierarchical)
					}

					if waypoint.lastUpdated != nil {
						Label {
							Text(waypoint.lastUpdated?.formatted(date: .numeric, time: .shortened) ?? "?")
								.foregroundStyle(.secondary)
						} icon: {
							Image(systemName: "clock.arrow.circlepath")
								.symbolRenderingMode(.hierarchical)
						}
					}

					if waypoint.expire != nil {
						Label {
							Text(waypoint.expire?.formatted(date: .numeric, time: .shortened) ?? "?")
								.foregroundStyle(.secondary)
						} icon: {
							Image(systemName: "hourglass.bottomhalf.filled")
								.symbolRenderingMode(.hierarchical)
						}
					}
				} header: {
					Text("Timestamps")
				}
			}
			.navigationTitle(waypoint.name ?? "Waypoint")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				if !waypoint.locked {
					ToolbarItem(placement: .topBarTrailing) {
						Button {
							editMode = true
							selectedDetent = .fraction(0.85)
						} label: {
							Image(systemName: "square.and.pencil")
						}
					}
				}
			}
		}
		} // Group
		} // NavigationStack
		.background(Color(.systemGroupedBackground))
		.fullScreenCover(isPresented: $showingBoundsSelector) {
			GeofenceBoundsSelectorView(
				center: CLLocationCoordinate2D(
					latitude: latitude != 0 ? latitude : (LocationsHandler.currentLocation?.latitude ?? 0),
					longitude: longitude != 0 ? longitude : (LocationsHandler.currentLocation?.longitude ?? 0)
				),
				initialBounds: geofenceBounds
			) { newBounds in
				geofenceBounds = newBounds
			}
		}
		.alert("Waypoint Failed to Send", isPresented: $waypointFailedAlert) {
					Button("OK", role: .cancel) {
						context.delete(waypoint)
						do {
							try context.save()
						} catch {
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
						Logger.mesh.error("Failed to save context on waypoint deletion: \(error)")
					}
				}
		}
		.task {
			await fetchNodeInfo()
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
				if waypoint.locked {
					locked = true
				}
				geofenceRadius = Double(waypoint.geofenceRadius)
				notifyOnEnter = waypoint.notifyOnEnter
				notifyOnExit = waypoint.notifyOnExit
				notifyFavoritesOnly = waypoint.notifyFavoritesOnly
				if waypoint.hasBoundingBox {
					geofenceBounds = GeoBounds(
						minLon: Double(waypoint.boundingBoxLongitudeWestI) / 1e7,
						minLat: Double(waypoint.boundingBoxLatitudeSouthI) / 1e7,
						maxLon: Double(waypoint.boundingBoxLongitudeEastI) / 1e7,
						maxLat: Double(waypoint.boundingBoxLatitudeNorthI) / 1e7
					)
				}
			} else {
				name = ""
				description = ""
				locked = false
				geofenceRadius = 0
				notifyOnEnter = false
				notifyOnExit = false
				notifyFavoritesOnly = false
				geofenceBounds = nil
				expires = false
				expire = Date.now.addingTimeInterval(60 * 480)
				icon = "📍"
				latitude = waypoint.mapCoordinate.latitude
				longitude = waypoint.mapCoordinate.longitude
			}
		}
		.presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.85)))
		#if !targetEnvironment(macCatalyst)
		.presentationDragIndicator(.visible)
		#endif

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
	}
	
	private func applyGeofence(to waypointProto: inout Waypoint) {
		waypointProto.geofenceRadius = UInt32(max(0, geofenceRadius).rounded())
		// The notification toggles are hidden in the UI when no geofence exists, but their
		// @State values persist. Normalize before serializing so turning a geofence off can't
		// leak stale `true` flags onto the mesh; favorites-only only applies when notifying.
		let hasGeofence = geofenceRadius > 0 || geofenceBounds != nil
		let serializedNotifyOnEnter = hasGeofence && notifyOnEnter
		let serializedNotifyOnExit = hasGeofence && notifyOnExit
		waypointProto.notifyOnEnter = serializedNotifyOnEnter
		waypointProto.notifyOnExit = serializedNotifyOnExit
		waypointProto.notifyFavoritesOnly = (serializedNotifyOnEnter || serializedNotifyOnExit) && notifyFavoritesOnly
		if let b = geofenceBounds {
			var box = BoundingBox()
			box.longitudeWestI = Int32((b.minLon * 1e7).rounded())
			box.latitudeSouthI = Int32((b.minLat * 1e7).rounded())
			box.longitudeEastI = Int32((b.maxLon * 1e7).rounded())
			box.latitudeNorthI = Int32((b.maxLat * 1e7).rounded())
			waypointProto.boundingBox = box
		}
		// No geofenceBounds -> leave boundingBox unset (cleared on the mesh).
	}

	@MainActor
	private func fetchNodeInfo() async {
		// --- Fetch createdBy node ---
		if waypoint.createdBy != 0 {
			let createdByNum = Int64(waypoint.createdBy)
			var createdByDescriptor = FetchDescriptor<NodeInfoEntity>(
				predicate: #Predicate<NodeInfoEntity> { $0.num == createdByNum }
			)
			createdByDescriptor.fetchLimit = 1

			do {
				let nodes = try context.fetch(createdByDescriptor)
				createdByNode = nodes.first
			} catch {
				Logger.services.warning("Error fetching createdBy node: \(error.localizedDescription)")
			}
		}

		// --- Fetch lastUpdatedBy node (only if different from createdBy) ---
		if waypoint.lastUpdatedBy != 0,
		   waypoint.lastUpdatedBy != waypoint.createdBy {
			let updatedByNum = Int64(waypoint.lastUpdatedBy)
			var updatedByDescriptor = FetchDescriptor<NodeInfoEntity>(
				predicate: #Predicate<NodeInfoEntity> { $0.num == updatedByNum }
			)
			updatedByDescriptor.fetchLimit = 1

			do {
				let nodes = try context.fetch(updatedByDescriptor)
				lastUpdatedByNode = nodes.first
			} catch {
				Logger.services.warning("Error fetching lastUpdatedBy node: \(error.localizedDescription)")
			}
		}
	}
}
