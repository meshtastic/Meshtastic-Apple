//
//  Routes.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 11/21/23.
//

import SwiftUI
import CoreData
import MapKit
import OSLog

@available(iOS 17.0, macOS 14.0, *)
struct Routes: View {

	@State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var selectedRoute: RouteEntity?
	@State private var importing = false
	@State private var isShowingBadFileAlert = false
	@State var isExporting = false
	@State var exportString = ""

	@State var hasChanges = false
	@State var name = ""
	@State var notes = ""
	@State var enabled = true
	@State var color = Color(red: 51, green: 199, blue: 88)

	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "enabled", ascending: false), NSSortDescriptor(key: "name", ascending: true), NSSortDescriptor(key: "date", ascending: false)], animation: .default)

	var routes: FetchedResults<RouteEntity>
	var body: some View {

		VStack {
			if selectedRoute == nil {
				Button("Import Route") {
					importing = true
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()

				.alert(isPresented: $isShowingBadFileAlert) {
					Alert(title: Text("Not a valid route file"), message: Text("Your route file must have both Latitude and Longitude columns and headers."), dismissButton: .default(Text("OK")))
				}
				.fileImporter(
					isPresented: $importing,
					allowedContentTypes: [.commaSeparatedText],
					allowsMultipleSelection: false
				) { result in
					do {
						guard let selectedFile: URL = try result.get().first else { return }
						guard selectedFile.startAccessingSecurityScopedResource() else {
							return
						}

						do {

							guard let fileContent = String(data: try Data(contentsOf: selectedFile), encoding: .utf8) else { return }
							let routeName = selectedFile.lastPathComponent.dropLast(4)
							let lines = fileContent.components(separatedBy: "\n")
							let headers = lines.first?.components(separatedBy: ",")
							var latIndex = -1
							var longIndex = -1
							for index in headers!.indices {
								Logger.services.debug("\(index): \( headers![index])")
								if headers![index].trimmingCharacters(in: .whitespaces) == "Latitude" {
									latIndex = index
								} else if headers![index].trimmingCharacters(in: .whitespaces) == "Longitude" {
									longIndex = index
								}
							}
							if latIndex >= 0 && longIndex >= 0 {
								let newRoute = RouteEntity(context: context)
								newRoute.name = String(routeName)
								newRoute.id = Int32.random(in: Int32(Int8.max) ... Int32.max)
								newRoute.color = Int64(UIColor.random.hex)
								newRoute.date = Date()
								newRoute.enabled = true
								var newLocations = [LocationEntity]()
								lines.dropFirst().forEach { line in
									let data = line.components(separatedBy: ",")
									if data.count > 1 {
										let latitude = latIndex >= 0 ? data[latIndex].trimmingCharacters(in: .whitespaces) : "0"
										let longitude = longIndex >= 0 ? data[longIndex].trimmingCharacters(in: .whitespaces) : "0"
										let loc = LocationEntity(context: context)
										loc.latitudeI = Int32((Double(latitude) ?? 0) * 1e7)
										loc.longitudeI = Int32((Double(longitude) ?? 0) * 1e7)
										newLocations.append(loc)
									}
								}
								newRoute.locations? = NSOrderedSet(array: newLocations)
								do {
									try context.save()
								} catch let error as NSError {
									Logger.services.error("\(error.localizedDescription)")
									isShowingBadFileAlert = true
								}
							} else {
								isShowingBadFileAlert = true
							}

						} catch {
							// TODO: deal with errors
							Logger.services.error("\(error.localizedDescription)")
						}

					} catch {
						Logger.services.error("CSV Import Error: \(error.localizedDescription)")
					}
				}
				List(routes, id: \.self, selection: $selectedRoute) { route in
					let routeColor = Color(UIColor(hex: route.color >= 0 ? UInt32(route.color) : 0))
					Label {
						VStack(alignment: .leading) {
							Text("\(route.name ?? "No Name Route")")
								.padding(.top)
								.foregroundStyle(.primary)

							Text("\(route.date?.formatted() ?? "Unknown Time")")
								.padding(.bottom)
								.font(.callout)
								.foregroundColor(.gray)

							if route.notes?.count ?? 0 > 0 {
								Text("\(route.notes ?? "")")
									.padding(.bottom)
									.font(.callout)
									.foregroundColor(.gray)
							}
						}
					} icon: {
						ZStack {
							Circle()
								.fill(routeColor)
								.frame(width: 40, height: 40)
								.padding(.top)
							if route.enabled {
								Image(systemName: "checkmark.circle.fill")
									.padding(.top)
									.foregroundColor(routeColor.isLight() ? .black : .white)
							}
						}
					}
					.badge(Text("\(Image(systemName: "mappin.and.ellipse")) \(route.locations?.count ?? 0)"))
							.font(.headline)
					.swipeActions {
						Button(role: .destructive) {
							context.delete(route)
							do {
								try context.save()
							} catch let error as NSError {
								Logger.data.error("\(error.localizedDescription)")
							}
						} label: {
							Label("delete", systemImage: "trash")
						}
					}

				}
				.listStyle(.plain)
			} else {
				VStack {
					if selectedRoute != nil {
						let locationArray = selectedRoute?.locations?.array as? [LocationEntity] ?? []
						let lineCoords = locationArray.compactMap({(location) -> CLLocationCoordinate2D in
							return location.locationCoordinate ?? LocationHelper.DefaultLocation
						})
						Form {
							TextField(
								"Name",
								text: $name,
								axis: .vertical
							)
							.foregroundColor(Color.gray)
							.onChange(of: name, perform: { _ in
								let totalBytes = name.utf8.count
								// Only mess with the value if it is too big

								if totalBytes > 100 {
									name = String(name.dropLast())
								}
							})

							Toggle(isOn: $enabled) {
								Label("enabled", systemImage: "point.topleft.filled.down.to.point.bottomright.curvepath")
								Text("Show on the mesh map.")
							}
							.toggleStyle(SwitchToggleStyle(tint: .accentColor))

							ColorPicker("Color", selection: $color, supportsOpacity: false)

							TextField(
								"Notes",
								text: $notes,
								axis: .vertical
							)
							.lineLimit(3...5)
							.foregroundColor(Color.gray)
						}
						.onAppear {
							name = selectedRoute?.name ?? "unknown".localized
							notes = selectedRoute?.notes ?? ""
							enabled = selectedRoute?.enabled ?? false
							color = Color(UIColor(hex: UInt32(selectedRoute?.color ?? 0)))
							hasChanges = false
						}
						HStack {

							Button("cancel", role: .cancel) {
								selectedRoute = nil
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.large)

							Button("save") {
								selectedRoute?.name = name
								selectedRoute?.notes = notes
								selectedRoute?.enabled = enabled
								selectedRoute?.color = Int64(UIColor(color).hex)
								do {
									try context.save()
									selectedRoute = nil
									Logger.data.info("💾 Saved a route")
								} catch {
									context.rollback()
									let nsError = error as NSError
									Logger.data.error("Error Saving RouteEntity from the Route Editor \(nsError)")
								}
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.large)
							.disabled(!hasChanges)
						}
						.onChange(of: name) { _ in
							hasChanges = true
						}
						.onChange(of: notes) { _ in
							hasChanges = true
						}
						.onChange(of: enabled) { _ in
							hasChanges = true
						}
						.onChange(of: color) { _ in
							hasChanges = true
						}
						Map {
							Annotation("Start", coordinate: lineCoords.first ?? LocationHelper.DefaultLocation) {
								ZStack {
									Circle()
										.fill(Color(.green))
										.strokeBorder(.white, lineWidth: 3)
										.frame(width: 15, height: 15)
								}
							}
							.annotationTitles(.automatic)
							Annotation("Finish", coordinate: lineCoords.last ?? LocationHelper.DefaultLocation) {
								ZStack {
									Circle()
										.fill(Color(.black))
										.strokeBorder(.white, lineWidth: 3)
										.frame(width: 15, height: 15)
								}
							}
							.annotationTitles(.automatic)
							let solid = StrokeStyle(
								lineWidth: 3,
								lineCap: .round, lineJoin: .round
							)
							MapPolyline(coordinates: lineCoords)
								.stroke(Color(UIColor(hex: UInt32(selectedRoute?.color ?? 0))), style: solid)
						}
						.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
						.safeAreaInset(edge: .bottom, alignment: UIDevice.current.userInterfaceIdiom == .phone ? .leading : .trailing) {
							Button {
								exportString = routeToCsvFile(locations: selectedRoute!.locations!.array as? [LocationEntity] ?? [])
								isExporting = true
							} label: {
								Label("export", systemImage: "square.and.arrow.down")
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.large)
							.padding(.bottom)
							.padding(.leading)
						}
					}
				}
				.fileExporter(
					isPresented: $isExporting,
					document: CsvDocument(emptyCsv: exportString),
					contentType: .commaSeparatedText,
					defaultFilename: String("\(selectedRoute?.name ?? "Route") Log"),
					onCompletion: { result in
						switch result {
						case .success:
							self.isExporting = false
							Logger.services.info("Route log download succeeded.")
						case .failure(let error):
							Logger.services.error("Route log download failed: \(error.localizedDescription).")
						}
					}
				)
			}
		}
		.navigationTitle(selectedRoute != nil ? name : "Route List")
		.navigationBarTitleDisplayMode(.inline)
	}
}
