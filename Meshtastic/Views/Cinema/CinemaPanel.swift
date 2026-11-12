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
	/// The stone the castle tower is built of.
	@Binding var stone: CastleStone
	/// The summits the fire lookout can stand on, highest first, the headlands the lighthouse can,
	/// best first, or the rooftops the city rooftop can, tallest first; empty with no downloaded
	/// terrain.
	let sites: [LookoutSite]
	/// The chosen site's id, or empty for the painted view.
	@Binding var siteID: String
	/// Sixteenth turns clockwise the lookout or the lighthouse is turned.
	@Binding var turns: Int
	/// Where the connected radio is, to say how far each summit is from it.
	let radioCoordinate: CLLocationCoordinate2D?
	/// Why there is no summit to pick, while there isn't.
	let lookoutNote: String?
	/// Whether the 3D map is showing or on its way; the button to open it is only there while not.
	let spatialMapOpen: Bool
	let onOpenSpatialMap: () -> Void
	/// Opens the 3D map zoomed in on the city rooftop, or the sky deck's tower, with the buildings on.
	let onShowRooftop: () -> Void
	let onLeave: () -> Void
	/// Which side of Earth is under the space station's cupola, and how fast the ground goes by.
	@AppStorage(CinemaEarthSide.key) private var earthSide: CinemaEarthSide = .day
	@AppStorage(CinemaOrbit.speedKey) private var earthSpeed = 1

	var body: some View {
		VStack(spacing: 12) {
			Picker(String(localized: "Environment", comment: "Cinema: picker for the place the big screen is set in"), selection: $environment) {
				ForEach(CinemaEnvironment.allCases) { environment in
					Text(environment.title).tag(environment)
				}
			}
			.pickerStyle(.menu)
			if environment.hasStone {
				Picker(String(localized: "Stone", comment: "Cinema: picker for the stone the castle tower is built of"), selection: $stone) {
					ForEach(CastleStone.allCases) { stone in
						Text(stone.title).tag(stone)
					}
				}
				.pickerStyle(.segmented)
				.frame(maxWidth: 260)
			}
			if environment == .spaceStation {
				Picker(String(localized: "Side of Earth", comment: "Cinema: picker for whether the sunlit or the dark side of Earth is under the space station's cupola"), selection: $earthSide) {
					ForEach(CinemaEarthSide.allCases) { side in
						Text(side.title).tag(side)
					}
				}
				.pickerStyle(.segmented)
				.frame(maxWidth: 260)
				VStack(spacing: 4) {
					Text("Orbit Speed \(CinemaOrbit.speed(earthSpeed))×", comment: "Cinema: how many times faster than real time Earth goes by under the space station; the argument is the multiple, e.g. 3")
						.font(.callout)
					Slider(value: Binding(get: { Double(CinemaOrbit.speed(earthSpeed)) }, set: { earthSpeed = CinemaOrbit.speed(Int($0.rounded())) }), in: 1...Double(CinemaOrbit.maximumSpeed), step: 1) {
						Text("Orbit Speed", comment: "Cinema: slider for how many times faster than real time Earth goes by under the space station")
					}
					.frame(maxWidth: 260)
				}
			}
			if environment.standsOnSite, !sites.isEmpty {
				Picker(sitePickerTitle, selection: $siteID) {
					switch environment.siteKind {
					case .coast:
						Text("Sea view", comment: "Cinema: the lighthouse's rendered view of the sea, with no real terrain")
							.tag("")
					case .rooftop, .skyDeck:
						Text("City skyline", comment: "Cinema: the city rooftop's rendered skyline, with no real buildings")
							.tag("")
					default:
						Text("Forest sunset", comment: "Cinema: the fire lookout's rendered forest view, with no real terrain")
							.tag("")
					}
					ForEach(sites) { site in
						Text(verbatim: title(for: site)).tag(site.id)
					}
				}
				.pickerStyle(.menu)
				// The world turns round the cab, so the screen looks out over another part of the
				// view. The forest sunset is painted, so there's nothing to turn there.
				if !siteID.isEmpty {
					LookoutTurnDial(title: environment.turnDialTitle, turns: $turns)
					if environment.siteKind == .skyDeck {
						Button(action: onShowRooftop) {
							Label(String(localized: "Show Tower", comment: "Cinema: button that opens the 3D map zoomed in on the tower the sky deck hangs off, with the buildings on"), systemImage: "building.2.crop.circle")
						}
					} else if environment.siteKind == .rooftop {
						Button(action: onShowRooftop) {
							Label(String(localized: "Show Rooftop", comment: "Cinema: button that opens the 3D map zoomed in on the city rooftop, with the buildings on"), systemImage: "building.2.crop.circle")
						}
					}
				}
			} else if environment.standsOnSite, let lookoutNote {
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

	/// The site picker's title: what the environment stands on.
	private var sitePickerTitle: String {
		switch environment.siteKind {
		case .coast:
			String(localized: "Headland", comment: "Cinema: picker for the headland on the coast the lighthouse stands on")
		case .rooftop:
			String(localized: "Rooftop", comment: "Cinema: picker for the building the city rooftop stands on")
		case .skyDeck:
			String(localized: "Tower", comment: "Cinema: picker for the tower the sky deck hangs off")
		default:
			String(localized: "Summit", comment: "Cinema: picker for the summit the fire lookout stands on")
		}
	}

	/// The summit's height, or how tall the building is, and how far from the radio and which way,
	/// when the radio has a position. A headland says which way it looks out to sea before its height.
	private func title(for site: LookoutSite) -> String {
		let unit: UnitLength = Locale.current.measurementSystem == .metric ? .meters : .feet
		let height = Measurement(value: Double(site.rooftop ?? site.elevation), unit: UnitLength.meters).converted(to: unit)
			.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
		let named: String
		if site.rooftop != nil {
			let tall = String(localized: "\(height) tall", comment: "Cinema: a building in the rooftop picker, by how tall it is")
			// A sky deck says which way it looks out from its tower first.
			named = site.facing.map { "\(SpatialLookout.facing(heading: $0)), \(tall)" } ?? tall
		} else {
			let label = site.name ?? site.facing.map { SpatialLookout.facing(heading: $0) }
			named = label.map { "\($0), \(height)" } ?? height
		}
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
