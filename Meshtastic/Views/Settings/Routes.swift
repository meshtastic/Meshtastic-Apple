//
//  Routes.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 11/21/23.
//

import SwiftUI
import CoreData
import MapKit

@available(iOS 17.0, macOS 14.0, *)
struct Routes: View {
	
	@State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var selectedRoute: RouteEntity?
	@State private var importing = false
	
	@FetchRequest(sortDescriptors: [], animation: .default)
	
	var routes: FetchedResults<RouteEntity>
	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			Button("Import Route") {
				importing = true
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
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
							print("\(index): \( headers![index])")
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
									print("Longitude: \(longitude) Latitude: \(latitude)")
								}
							}
							newRoute.locations? = NSOrderedSet(array: newLocations)
							do {
								try context.save()
							} catch let error as NSError {
								print("Error: \(error.localizedDescription)")
							}
						}
						
					} catch {
						print("error: \(error)") // to do deal with errors
					}
					
				} catch {
					print("CSV Import Error")
				}
			}
			
			VStack {
				List(routes, id: \.self, selection: $selectedRoute) { route in
					Label {
						VStack (alignment: .leading) {
							Text("\(route.name ?? "No Name Route")")
								.padding(.top)
								.foregroundStyle(.primary)
							
							Text("\(route.date?.formatted() ?? "Unknown Time")")
								.padding(.bottom)
								.font(.callout)
								.foregroundColor(.gray)
						}
					} icon: {
						RoundedRectangle(cornerRadius: 10)
							.fill(Color(UIColor(hex: route.color >= 0 ? UInt32(route.color) : 0)))
							.frame(width: 20, height: 20)
					}
				}
				.listStyle(.plain)
			}
			.navigationTitle("Route List")
		} detail: {
			VStack {
				if selectedRoute != nil {
					let locationArray = selectedRoute?.locations?.array as? [LocationEntity] ?? []
					let lineCoords = locationArray.compactMap({(location) -> CLLocationCoordinate2D in
						return location.locationCoordinate ?? LocationHelper.DefaultLocation
					})
					
					Map() {
						Annotation("Start", coordinate: lineCoords.first ?? LocationHelper.DefaultLocation) {
							ZStack {
								Circle()
									.fill(Color(.green))
									.strokeBorder(.white, lineWidth: 3)
									.frame(width: 15, height: 15)
							}
						}
						.annotationTitles(.automatic)
						Annotation("Finish", coordinate: locationArray.last?.locationCoordinate ?? LocationHelper.DefaultLocation) {
							ZStack {
								Circle()
									.fill(Color(.black))
									.strokeBorder(.white, lineWidth: 3)
									.frame(width: 15, height: 15)
							}
						}
						.annotationTitles(.automatic)
						let dashed = StrokeStyle(
							lineWidth: 3,
							lineCap: .round, lineJoin: .round, dash: [7, 10]
						)
						MapPolyline(coordinates: lineCoords)
							.stroke(Color(UIColor(hex: UInt32(selectedRoute?.color ?? 0))), style: dashed)
					}
					.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}.navigationTitle(" \(selectedRoute?.name ?? "Unknown Route") \(selectedRoute?.locations?.count ?? 0) points")
		}
	}
}
