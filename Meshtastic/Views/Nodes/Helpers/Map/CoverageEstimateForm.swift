//
//  CoverageEstimateForm.swift
//  Meshtastic
//
//  The estimate form for an in-app Site Planner coverage run. Mirrors the
//  planner's `Site Parameters` panels — Site / Transmitter → Receiver →
//  Simulation Options → Display, with Transmitter + Display open and the rest
//  collapsed. Submitting drives `CoverageEstimateRunner` (headless WebView +
//  bridge) and, on success, imports the styled GeoJSON as a map overlay.
//
//  See meshtastic/Meshtastic-Apple#2058.
//

import SwiftUI
import CoreLocation

/// Seed for presenting the estimate form: the prefilled parameters plus the
/// coordinates available as one-tap location shortcuts.
struct CoverageEstimateSeed: Identifiable {
	let id = UUID()
	var parameters: SitePlannerParameters
	/// The selected node's coordinate, when launched from a node.
	var nodeCoordinate: CLLocationCoordinate2D?
	/// The current map centre, when launched from the map toolbar.
	var mapCenter: CLLocationCoordinate2D?
}

struct CoverageEstimateForm: View {

	let seed: CoverageEstimateSeed
	@ObservedObject var runner: CoverageEstimateRunner

	@Environment(\.dismiss) private var dismiss

	@State private var params: SitePlannerParameters
	@State private var errorMessage: String?
	/// In-flight reverse geocode for the chosen coordinate; cancelled when a newer coordinate is picked.
	@State private var geocodeTask: Task<Void, Never>?

	init(seed: CoverageEstimateSeed, runner: CoverageEstimateRunner) {
		self.seed = seed
		self.runner = runner
		_params = State(initialValue: seed.parameters)
	}

	private var deviceLocation: CLLocationCoordinate2D? {
		LocationsHandler.currentLocation
	}

	var body: some View {
		NavigationStack {
			Form {
				transmitterSection
				receiverSection
				simulationSection
				displaySection
			}
			.scrollDismissesKeyboard(.immediately)
			.navigationTitle("Estimate Coverage")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						runner.reset()
						dismiss()
					} label: {
						Image(systemName: "xmark.circle.fill")
							.font(.title2)
							.symbolRenderingMode(.palette)
							.foregroundStyle(.white, Color(.systemGray3))
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Close")
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Estimate") {
						runner.start(params: params)
					}
					.disabled(!params.isValid || runner.isRunning)
				}
			}
			.overlay {
				if runner.isRunning {
					estimatingOverlay
				}
			}
			.onAppear(perform: generateInitialNameIfNeeded)
			.onDisappear {
				// Tear down a still-running headless run if the sheet is swipe-dismissed. Safe on the
				// success path too — the import already published its result before `dismiss()`.
				runner.reset()
			}
			.onChange(of: runner.state) { _, newState in
				switch newState {
				case .imported:
					dismiss()
				case let .failed(message):
					errorMessage = message
				default:
					break
				}
			}
			.alert("Coverage estimate failed", isPresented: Binding(
				get: { errorMessage != nil },
				set: { if !$0 { errorMessage = nil } }
			)) {
				Button("OK", role: .cancel) { runner.reset() }
			} message: {
				Text(errorMessage ?? "")
			}
		}
	}

	// MARK: - Sections

	private var transmitterSection: some View {
		Section {
			TextField("Site name", text: $params.name)
				.accessibilityLabel("Site name")

			locationShortcuts

			DecimalField("Latitude", value: $params.latitude)
			DecimalField("Longitude", value: $params.longitude)
			labeledNumber("Transmit power (W)", value: $params.txPowerWatts)
			labeledNumber("Frequency (MHz)", value: $params.txFrequencyMHz)
			lengthField("Antenna height", canonical: $params.txHeightMeters, storedUnit: .meters, imperialUnit: .feet)
			labeledNumber("Antenna gain (dBi)", value: $params.txGainDBi)
		} header: {
			Label {
				Text("Site / Transmitter")
			} icon: {
				Image("custom.radio.tower")
			}
		}
	}

	private var receiverSection: some View {
		Section {
			DecimalField("Sensitivity (dBm)", value: $params.rxSensitivityDBm)
		} header: {
			Label("Receiver", systemImage: "dot.radiowaves.left.and.right")
		}
	}

	private var simulationSection: some View {
		Section {
			lengthField("Max range", canonical: $params.maxRangeKm, storedUnit: .kilometers, imperialUnit: .miles)
			Toggle("High-resolution terrain", isOn: $params.highResolution)
				.onChange(of: params.highResolution) { _, _ in
					// High-res caps the range at 70 km — clamp so the value stays valid.
					let bounds = params.maxRangeBounds
					params.maxRangeKm = min(max(params.maxRangeKm, bounds.lowerBound), bounds.upperBound)
				}
		} header: {
			Label("Simulation Options", systemImage: "slider.horizontal.3")
		} footer: {
			Text("High-resolution terrain gives a more detailed estimate but caps the maximum range at 70 km.")
		}
	}

	private var displaySection: some View {
		Section {
			Picker("Palette", selection: $params.colorScale) {
				ForEach(SitePlannerColorScale.allCases) { scale in
					Text(scale.displayName).tag(scale)
				}
			}
		} header: {
			Label("Display", systemImage: "paintpalette")
		}
	}

	// MARK: - Location shortcuts

	@ViewBuilder private var locationShortcuts: some View {
		let hasShortcuts = deviceLocation != nil || seed.nodeCoordinate != nil || seed.mapCenter != nil
		if hasShortcuts {
			VStack(alignment: .leading, spacing: 6) {
				Text("Set coordinates from")
					.font(.caption)
					.foregroundStyle(.secondary)
				HStack(spacing: 8) {
					if let device = deviceLocation {
						shortcutButton("My Location", systemImage: "location.fill") { apply(device) }
					}
					if let node = seed.nodeCoordinate {
						shortcutButton("Node", systemImage: "flipphone") { apply(node) }
					}
					if let center = seed.mapCenter {
						shortcutButton("Map Center", systemImage: "scope") { apply(center) }
					}
				}
				.buttonStyle(.bordered)
			}
		}
	}

	/// A compact equal-width shortcut cell: icon over a single-line label, so long titles
	/// ("My Location", "Map Center") don't wrap or hyphenate in the three-across row.
	private func shortcutButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(spacing: 4) {
				Image(systemName: systemImage)
					.font(.body)
				Text(title)
					.font(.caption2)
					.lineLimit(1)
					.minimumScaleFactor(0.75)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 4)
		}
		.accessibilityLabel(Text(title))
		.accessibilityHint("Fills the transmitter coordinates.")
	}

	private func apply(_ coordinate: CLLocationCoordinate2D) {
		params.latitude = coordinate.latitude
		params.longitude = coordinate.longitude
		reverseGeocodeName(for: coordinate)
	}

	/// Auto-fills the site name from the chosen coordinate's placemark. Prefers a named point of
	/// interest (coverage sites are usually a landmark/hill/park/tower), then the placemark name,
	/// then progressively coarser locality/street/water fields. Cancels any in-flight lookup so the
	/// newest pick wins, and leaves the existing name untouched when the geocode yields nothing or fails.
	/// On launch, if the site name is empty but the seed already carries a usable coordinate (e.g.
	/// presented from the map toolbar), reverse-geocode it to fill the name — the same result as
	/// tapping a location shortcut, just automatic. Skipped when a name is already set (the
	/// node-detail hand-off prefills the node's name) or the coordinate is the 0,0 sentinel.
	private func generateInitialNameIfNeeded() {
		guard params.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			  params.hasValidCoordinate else { return }
		reverseGeocodeName(for: CLLocationCoordinate2D(latitude: params.latitude, longitude: params.longitude))
	}

	private func reverseGeocodeName(for coordinate: CLLocationCoordinate2D) {
		geocodeTask?.cancel()
		geocodeTask = Task {
			let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
			let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
			guard !Task.isCancelled, let placemark, let name = Self.siteName(from: placemark) else { return }
			await MainActor.run { params.name = name }
		}
	}

	/// Picks a human place name for a coordinate. Prefers a named point of interest, then the
	/// placemark's `name` ONLY when it isn't a street address (`CLPlacemark.name` degrades to the
	/// street address whenever there's no landmark), then neighborhood → city → street → water. This
	/// keeps residential coordinates from filling the field with "13500 SE Newport Way".
	static func siteName(from placemark: CLPlacemark) -> String? {
		if let poi = placemark.areasOfInterest?.first { return poi }
		if let name = placemark.name, !placemarkNameIsStreetAddress(name, placemark) { return name }
		return placemark.subLocality
			?? placemark.locality
			?? placemark.thoroughfare
			?? placemark.inlandWater
			?? placemark.ocean
	}

	/// `CLPlacemark.name` is the formatted street address when the placemark resolves to a building:
	/// a house number is present, or the name leads with a digit, or it contains the street name.
	private static func placemarkNameIsStreetAddress(_ name: String, _ placemark: CLPlacemark) -> Bool {
		if placemark.subThoroughfare != nil { return true }
		if name.first?.isNumber == true { return true }
		if let street = placemark.thoroughfare, name.localizedCaseInsensitiveContains(street) { return true }
		return false
	}

	// MARK: - Helpers

	private func labeledNumber(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
		HStack {
			Text(title)
			Spacer()
			TextField("", value: value, format: .number)
				.keyboardType(.decimalPad)
				.multilineTextAlignment(.trailing)
				.frame(maxWidth: 140)
				.accessibilityLabel(Text(title))
		}
	}

	/// An editable length field that keeps the model in its canonical unit (`storedUnit`, what the
	/// Site Planner expects) but displays and edits in the device locale's measurement system —
	/// `imperialUnit` for non-metric locales. `Measurement.FormatStyle` isn't `ParseableFormatStyle`,
	/// so a converting `Binding<Double>` bridges the two rather than a `format:` on the field. The
	/// number itself still formats per locale via `.number`.
	private func lengthField(_ title: LocalizedStringKey, canonical: Binding<Double>, storedUnit: UnitLength, imperialUnit: UnitLength) -> some View {
		let displayUnit = Locale.current.measurementSystem == .metric ? storedUnit : imperialUnit
		let display = Binding<Double>(
			get: { Measurement(value: canonical.wrappedValue, unit: storedUnit).converted(to: displayUnit).value },
			set: { canonical.wrappedValue = Measurement(value: $0, unit: displayUnit).converted(to: storedUnit).value }
		)
		return HStack {
			Text(title)
			Text(verbatim: "(\(displayUnit.symbol))")
				.foregroundStyle(.secondary)
			Spacer()
			TextField("", value: display, format: .number.precision(.fractionLength(0...2)))
				.keyboardType(.decimalPad)
				.multilineTextAlignment(.trailing)
				.frame(maxWidth: 140)
				.accessibilityLabel(Text(title))
		}
	}

	/// A text-backed decimal field for values that can be negative (latitude, longitude,
	/// receiver sensitivity). `TextField(value:format: .number)` resets the bound value to
	/// `nil` on intermediate input like a lone `-` or a trailing `.`, which makes negative
	/// values awkward to type. A local string buffer lets the user type freely and only
	/// pushes a parsed value back to the model, while still reflecting external updates
	/// (e.g. the location shortcut buttons) when the field isn't being edited.
	private struct DecimalField: View {
		let title: LocalizedStringKey
		@Binding var value: Double
		@State private var text: String
		@FocusState private var focused: Bool

		init(_ title: LocalizedStringKey, value: Binding<Double>) {
			self.title = title
			_value = value
			_text = State(initialValue: Self.format(value.wrappedValue))
		}

		var body: some View {
			HStack {
				Text(title)
				Spacer()
				TextField("", text: $text)
					.keyboardType(.numbersAndPunctuation)
					.multilineTextAlignment(.trailing)
					.frame(maxWidth: 140)
					.focused($focused)
					.accessibilityLabel(Text(title))
					.onChange(of: text) { _, newValue in
						if let parsed = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
							value = parsed
						}
					}
					.onChange(of: value) { _, newValue in
						// Reflect external updates (shortcut buttons), but don't fight the user mid-edit.
						if !focused {
							text = Self.format(newValue)
						}
					}
			}
		}

		/// Formats with a stable `.` decimal separator (matching `Double` parsing) and no
		/// grouping, trimming trailing zeros while preserving coordinate precision.
		private static func format(_ value: Double) -> String {
			let formatter = NumberFormatter()
			formatter.numberStyle = .decimal
			formatter.usesGroupingSeparator = false
			formatter.minimumFractionDigits = 0
			formatter.maximumFractionDigits = 8
			formatter.locale = Locale(identifier: "en_US_POSIX")
			return formatter.string(from: NSNumber(value: value)) ?? String(value)
		}
	}

	private var estimatingOverlay: some View {
		ZStack {
			Color(.systemBackground).opacity(0.85).ignoresSafeArea()
			VStack(spacing: 16) {
				ProgressView()
					.controlSize(.large)
				Text("Estimating coverage…")
					.font(.headline)
				Button("Cancel") {
					runner.reset()
				}
				.buttonStyle(.bordered)
			}
			.padding(24)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
		}
	}
}
