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
			.fileImporter(
				isPresented: $importing,
				allowedContentTypes: [.commaSeparatedText],
				allowsMultipleSelection: false
			) { result in
				do {
					guard let selectedFile: URL = try result.get().first else { return }
					
					guard selectedFile.startAccessingSecurityScopedResource() else { // Notice this line right here
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
							newRoute.name = ("\(String(routeName)) - \(Date().formatted())")
							newRoute.id = Int32.random(in: Int32(Int8.max) ... Int32.max)
							newRoute.color = 12
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
					Text(route.name ?? "No Name Route")
						.font(.title)
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
					
					Map () {
						
						let gradient = LinearGradient(
							colors: [.cyan, .blue, .secondary],//[Color(nodeColor.lighter().lighter()), Color(nodeColor.lighter()), Color(nodeColor)],
							startPoint: .leading, endPoint: .trailing
						)
						let dashed = StrokeStyle(
							lineWidth: 3,
							lineCap: .round, lineJoin: .round, dash: [10, 10]
						)
						MapPolyline(coordinates: lineCoords)
							.stroke(gradient, style: dashed)
					}
					.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}.navigationTitle(" \(selectedRoute?.name ?? "Unknown Route") Map")
		}
	}
}
