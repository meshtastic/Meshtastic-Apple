//
//  CinemaPanel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
#if os(visionOS)
import CoreLocation
import SwiftUI

/// The small panel near the viewer in the cinema: which environment to sit in, the 3D map while
/// it is closed, and Leave.
struct CinemaPanel: View {
	@Binding var environment: CinemaEnvironment
	/// The summits the fire lookout can stand on, highest first; empty with no downloaded terrain.
	let sites: [LookoutSite]
	/// The chosen summit's id, or empty for the painted sunset.
	@Binding var siteID: String
	/// Where the connected radio is, to say how far each summit is from it.
	let radioCoordinate: CLLocationCoordinate2D?
	/// Why there is no summit to pick, while there isn't.
	let lookoutNote: String?
	/// Whether the 3D map is showing or on its way; the button to open it is only there while not.
	let spatialMapOpen: Bool
	let onOpenSpatialMap: () -> Void
	let onLeave: () -> Void

	var body: some View {
		VStack(spacing: 12) {
			Picker(String(localized: "Environment", comment: "Cinema: picker for the place the big screen is set in"), selection: $environment) {
				ForEach(CinemaEnvironment.allCases) { environment in
					Text(environment.title).tag(environment)
				}
			}
			.pickerStyle(.menu)
			if environment.isCutout, !sites.isEmpty {
				Picker(String(localized: "Summit", comment: "Cinema: picker for the summit the fire lookout stands on"), selection: $siteID) {
					Text("Painted sunset", comment: "Cinema: the fire lookout's painted view, with no real terrain")
						.tag("")
					ForEach(sites) { site in
						Text(verbatim: title(for: site)).tag(site.id)
					}
				}
				.pickerStyle(.menu)
			} else if environment.isCutout, let lookoutNote {
				Text(verbatim: lookoutNote)
					.font(.caption)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.frame(maxWidth: 260)
			}
			if !spatialMapOpen {
				Button(action: onOpenSpatialMap) {
					Label {
						Text("Open 3D Map", comment: "Cinema: opens the 3D map volume from the panel in the immersive cinema")
					} icon: {
						Image("custom.map.wheel")
					}
				}
			}
			Button(role: .cancel, action: onLeave) {
				Label(String(localized: "Leave", comment: "Cinema: close the immersive cinema and go back to the app window"), systemImage: "xmark")
			}
		}
		.padding(20)
		.glassBackgroundEffect()
	}

	/// The summit's height, and how far from the radio and which way, when the radio has a position.
	private func title(for site: LookoutSite) -> String {
		let unit: UnitLength = Locale.current.measurementSystem == .metric ? .meters : .feet
		let height = Measurement(value: Double(site.elevation), unit: UnitLength.meters).converted(to: unit)
			.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
		let named = site.name.map { "\($0), \(height)" } ?? height
		guard let radioCoordinate else { return named }
		let distance = Measurement(value: radioCoordinate.distance(from: site.coordinate), unit: UnitLength.meters)
			.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
		let bearing = getBearingBetweenTwoPoints(
			point1: CLLocation(latitude: radioCoordinate.latitude, longitude: radioCoordinate.longitude),
			point2: CLLocation(latitude: site.latitude, longitude: site.longitude)
		)
		let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
		let point = points[Int(((bearing + 360 + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]
		return String(localized: "\(named), \(distance) \(point)", comment: "Cinema: a summit in the picker: its name and height, then how far from the radio and which way (N, NE, ...)")
	}
}
#endif
