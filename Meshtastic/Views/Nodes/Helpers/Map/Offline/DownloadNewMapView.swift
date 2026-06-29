//
//  DownloadNewMapView.swift
//  Meshtastic
//
//  Search for a place (or use the current location) to seed the area selector.
//

import SwiftUI
import MapKit
import CoreLocation
import OSLog

struct DownloadNewMapView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var manager = OfflineMapManager.shared
	@StateObject private var search = MapSearchCompleter()
	@State private var query = ""
	@State private var target: OfflineRegionTarget?
	@State private var resolving = false
	/// Reverse-geocoded name of the current location (e.g. "Bellevue"), shown as the row subtitle.
	@State private var currentPlaceName: String?

	/// Default framing for a freshly-picked place; the selector lets the user adjust.
	private let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)

	var body: some View {
		List {
			if query.isEmpty, let coordinate = LocationsHandler.currentPreciseLocation {
				Section {
					Button {
						target = OfflineRegionTarget(
							name: currentPlaceName ?? String(localized: "Current Location"),
							region: MKCoordinateRegion(center: coordinate, span: defaultSpan)
						)
					} label: {
						HStack(spacing: 12) {
							Image(systemName: "location.fill")
								.font(.system(size: 15, weight: .semibold))
								.foregroundStyle(Color.accentColor)
								.frame(width: 34, height: 34)
								.background(Circle().fill(Color(.systemGray5)))
							VStack(alignment: .leading, spacing: 1) {
								Text("Current Location")
									.foregroundStyle(.primary)
								if let currentPlaceName {
									Text(currentPlaceName)
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
						}
					}
				}
			}

			if !search.results.isEmpty {
				Section {
					ForEach(Array(search.results.enumerated()), id: \.offset) { _, completion in
						Button {
							Task { await resolve(completion) }
						} label: {
							VStack(alignment: .leading, spacing: 2) {
								Text(completion.title)
								if !completion.subtitle.isEmpty {
									Text(completion.subtitle)
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
						}
					}
				}
			}
		}
		.searchable(text: $query, prompt: Text("Cities, parks, and more"))
		.onChange(of: query) { _, newValue in search.update(newValue) }
		.task {
			guard currentPlaceName == nil, let coordinate = LocationsHandler.currentPreciseLocation else { return }
			currentPlaceName = await Self.placeName(for: coordinate)
		}
		.overlay {
			if resolving { ProgressView() }
		}
		.navigationTitle("Download New Map")
		.navigationBarTitleDisplayMode(.inline)
		.navigationDestination(item: $target) { target in
			RegionSelectorView(target: target)
		}
		.onChange(of: manager.isDownloading) { _, downloading in
			// When a download begins (from the selector), unwind back to the list.
			if downloading { dismiss() }
		}
	}

	/// Reverse-geocodes the current location to a short place name (city) for the row subtitle.
	private static func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
		let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
		let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
		return placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.name
	}

	private func resolve(_ completion: MKLocalSearchCompletion) async {
		resolving = true
		defer { resolving = false }
		let request = MKLocalSearch.Request(completion: completion)
		do {
			let response = try await MKLocalSearch(request: request).start()
			guard let item = response.mapItems.first else { return }
			let region = response.boundingRegion.span.latitudeDelta > 0
				? response.boundingRegion
				: MKCoordinateRegion(center: item.placemark.coordinate, span: defaultSpan)
			target = OfflineRegionTarget(name: completion.title, region: region)
		} catch {
			Logger.services.debug("🗺️ [Offline] Place search failed: \(error.localizedDescription, privacy: .public)")
		}
	}
}

/// Wraps `MKLocalSearchCompleter` as an observable source of autocomplete results.
@MainActor
final class MapSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
	@Published var results: [MKLocalSearchCompletion] = []
	private let completer = MKLocalSearchCompleter()

	override init() {
		super.init()
		completer.delegate = self
		completer.resultTypes = [.address, .pointOfInterest]
	}

	func update(_ text: String) {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty {
			results = []
		} else {
			completer.queryFragment = trimmed
		}
	}

	nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
		let results = completer.results
		Task { @MainActor in self.results = results }
	}

	nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
		Task { @MainActor in self.results = [] }
	}
}
