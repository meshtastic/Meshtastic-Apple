//
//  CoverageEstimateForm.swift
//  Meshtastic
//
//  The Site/Transmitter, Receiver, Simulation, and Display sections for a Site Planner
//  coverage estimate (spec 015, US1/US2), plus the Environment/advanced fields behind
//  a disclosure (US3, T023) — see data-model.md.
//
//  Height/range fields (antenna height, receiver height, max range) are edited via
//  Foundation's Measurement format style so they display in the user's locale unit
//  (feet/miles vs. meters/km) per the Design Standards §10 findings in research.md §6,
//  while CoverageEstimateParameters itself always stores metric SI values underneath —
//  conversion happens only at this presentation layer, never in the stored model or the
//  query the app eventually sends (contracts/query-contract.md, which is metric-only).
//

import SwiftUI
import OSLog

struct CoverageEstimateForm: View {

	@State private var parameters: CoverageEstimateParameters
	@State private var showAdvanced = false
	@ObservedObject private var coordinator = CoverageEstimateCoordinator.shared
	@Environment(\.dismiss) private var dismiss

	init(initialParameters: CoverageEstimateParameters, initiallyShowAdvanced: Bool = false) {
		_parameters = State(initialValue: initialParameters)
		_showAdvanced = State(initialValue: initiallyShowAdvanced)
	}

	var body: some View {
		NavigationStack {
			Form {
				if let validationMessage {
					Section {
						Label(validationMessage, systemImage: "exclamationmark.triangle")
							.foregroundStyle(.orange)
					}
				}
				siteTransmitterSection
				receiverSection
				simulationSection
				displaySection
				statusSection
			}
			.navigationTitle("Estimate Coverage")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") {
						if case .running = coordinator.state {
							coordinator.cancel()
						}
						dismiss()
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					submitButton
				}
			}
			.onChange(of: coordinator.state) { _, newState in
				if case .succeeded = newState {
					// Give the user a moment to see the success row before auto-dismissing.
					Task {
						try? await Task.sleep(for: .seconds(1))
						coordinator.acknowledge()
						dismiss()
					}
				}
			}
		}
	}

	// MARK: - Sections

	@ViewBuilder
	private var siteTransmitterSection: some View {
		Section("Site / Transmitter") {
			TextField("Name", text: $parameters.name)
			LabeledContent("Position") {
				Text(verbatim: String(format: "%.5f, %.5f", parameters.latitude, parameters.longitude))
					.foregroundStyle(.secondary)
			}
			HStack {
				Text("Transmit Power")
				Spacer()
				TextField("Transmit Power", value: $parameters.transmitPowerWatts, format: .number.precision(.fractionLength(0...3)))
					.multilineTextAlignment(.trailing)
					.keyboardType(.decimalPad)
				Text("W").foregroundStyle(.secondary)
			}
			HStack {
				Text("Frequency")
				Spacer()
				TextField("Frequency", value: $parameters.transmitFrequencyMHz, format: .number.precision(.fractionLength(0...3)))
					.multilineTextAlignment(.trailing)
					.keyboardType(.decimalPad)
				Text("MHz").foregroundStyle(.secondary)
			}
			LengthField(title: "Antenna Height", meters: $parameters.antennaHeightMeters)
			HStack {
				Text("Antenna Gain")
				Spacer()
				TextField("Antenna Gain", value: $parameters.antennaGainDBi, format: .number.precision(.fractionLength(0...1)))
					.multilineTextAlignment(.trailing)
					.keyboardType(.decimalPad)
				Text("dBi").foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private var receiverSection: some View {
		Section {
			HStack {
				Text("Sensitivity")
				Spacer()
				TextField("Sensitivity", value: $parameters.receiverSensitivityDBm, format: .number.precision(.fractionLength(0...1)))
					.multilineTextAlignment(.trailing)
					.keyboardType(.numbersAndPunctuation)
				Text("dBm").foregroundStyle(.secondary)
			}
			LengthField(title: "Receiver Height", meters: $parameters.receiverHeightMeters)
			HStack {
				Text("System Loss")
				Spacer()
				TextField("System Loss", value: $parameters.receiverLossDB, format: .number.precision(.fractionLength(0...1)))
					.multilineTextAlignment(.trailing)
					.keyboardType(.decimalPad)
				Text("dB").foregroundStyle(.secondary)
			}
		} header: {
			Text("Receiver")
		} footer: {
			// Design Standards §6: plain-language subtext for technical settings.
			Text("How sensitive a receiving radio is assumed to be — a lower (more negative) number means it can hear weaker signals.")
		}
	}

	@ViewBuilder
	private var simulationSection: some View {
		Section("Simulation") {
			RangeField(title: "Max Range", kilometers: $parameters.maxRangeKm, highResolution: parameters.highResolutionTerrain)
			Toggle("High-Resolution Terrain", isOn: $parameters.highResolutionTerrain)
			advancedDisclosure
		}
	}

	/// Environment fields + the Simulation section's advanced statistical parameters
	/// (US3, T023) — behind one disclosure so basic use (US1/US2) is unaffected. Each
	/// technical field carries plain-language subtext per Design Standards §6, since
	/// these are denser RF/ITM jargon than anything in the base sections.
	@ViewBuilder
	private var advancedDisclosure: some View {
		DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text("Situation Fraction")
					Spacer()
					TextField("Situation Fraction", value: optionalDoubleBinding(\.situationFraction), format: .number.precision(.fractionLength(0...2)), prompt: Text("Default"))
						.multilineTextAlignment(.trailing)
						.keyboardType(.decimalPad)
				}
				Text("How often the modeled signal level is expected to be met across the coverage area (0–1). Leave blank to use the planner's default.")
					.font(.caption).foregroundStyle(.secondary)
			}
			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text("Time Fraction")
					Spacer()
					TextField("Time Fraction", value: optionalDoubleBinding(\.timeFraction), format: .number.precision(.fractionLength(0...2)), prompt: Text("Default"))
						.multilineTextAlignment(.trailing)
						.keyboardType(.decimalPad)
				}
				Text("How often the modeled signal level is expected to be met over time at a given point (0–1). Leave blank to use the planner's default.")
					.font(.caption).foregroundStyle(.secondary)
			}
			Picker("Radio Climate", selection: $parameters.radioClimate) {
				ForEach(RadioClimate.allCases) { climate in
					Text(climate.queryValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(climate)
				}
			}
			Picker("Polarization", selection: $parameters.polarization) {
				ForEach(Polarization.allCases) { polarization in
					Text(polarization.rawValue.capitalized).tag(polarization)
				}
			}
			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text("Clutter Height")
					Spacer()
					TextField("Clutter Height", value: optionalDoubleBinding(\.clutterHeightMeters), format: .number.precision(.fractionLength(0...1)), prompt: Text("Default"))
						.multilineTextAlignment(.trailing)
						.keyboardType(.decimalPad)
					Text("m").foregroundStyle(.secondary)
				}
				Text("Height of trees/buildings assumed to surround the receiver.")
					.font(.caption).foregroundStyle(.secondary)
			}
			HStack {
				Text("Ground Dielectric")
				Spacer()
				TextField("Ground Dielectric", value: optionalDoubleBinding(\.groundDielectric), format: .number.precision(.fractionLength(0...2)), prompt: Text("Default"))
					.multilineTextAlignment(.trailing)
					.keyboardType(.decimalPad)
			}
			HStack {
				Text("Ground Conductivity")
				Spacer()
				TextField("Ground Conductivity", value: optionalDoubleBinding(\.groundConductivity), format: .number.precision(.fractionLength(0...4)), prompt: Text("Default"))
					.multilineTextAlignment(.trailing)
					.keyboardType(.decimalPad)
				Text("S/m").foregroundStyle(.secondary)
			}
			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text("Atmosphere Bending")
					Spacer()
					TextField("Atmosphere Bending", value: optionalDoubleBinding(\.atmosphereBending), format: .number.precision(.fractionLength(0...1)), prompt: Text("Default"))
						.multilineTextAlignment(.trailing)
						.keyboardType(.decimalPad)
					Text("N/km").foregroundStyle(.secondary)
				}
				Text("How much the radio signal curves to follow the Earth — higher values let it reach further past the horizon.")
					.font(.caption).foregroundStyle(.secondary)
			}
		}
	}

	/// Bridges an optional `Double` field to a `TextField` binding: an empty field means
	/// "unset" (the planner's own default applies, per contracts/query-contract.md's
	/// omission rule), typing a value sets it, clearing the field back to empty un-sets it.
	private func optionalDoubleBinding(_ keyPath: WritableKeyPath<CoverageEstimateParameters, Double?>) -> Binding<Double?> {
		Binding(get: { parameters[keyPath: keyPath] }, set: { parameters[keyPath: keyPath] = $0 })
	}

	@ViewBuilder
	private var displaySection: some View {
		Section("Display") {
			Picker("Color Palette", selection: $parameters.colorScale) {
				ForEach(ColorScale.allCases) { scale in
					Text(scale.rawValue.capitalized).tag(scale)
				}
			}
			HStack {
				Text("Min")
				Spacer()
				TextField("Min", value: $parameters.minDBm, format: .number.precision(.fractionLength(0...1)))
					.multilineTextAlignment(.trailing)
					.keyboardType(.numbersAndPunctuation)
				Text("dBm").foregroundStyle(.secondary)
			}
			HStack {
				Text("Max")
				Spacer()
				TextField("Max", value: $parameters.maxDBm, format: .number.precision(.fractionLength(0...1)))
					.multilineTextAlignment(.trailing)
					.keyboardType(.numbersAndPunctuation)
				Text("dBm").foregroundStyle(.secondary)
			}
			HStack {
				Text("Overlay Transparency")
				Spacer()
				TextField("Overlay Transparency", value: $parameters.overlayTransparencyPercent, format: .number.precision(.fractionLength(0...0)))
					.multilineTextAlignment(.trailing)
					.keyboardType(.numberPad)
				Text("%").foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private var statusSection: some View {
		switch coordinator.state {
		case .running:
			Section {
				HStack {
					ProgressView()
					Text("Estimating coverage…")
				}
			}
		case .succeeded:
			Section {
				Label("Coverage added to the map", systemImage: "checkmark.circle.fill")
					.foregroundStyle(.green)
			}
		case .failed(let reason):
			Section {
				Label(reason.localizedDescription ?? "The estimate failed.", systemImage: "xmark.octagon.fill")
					.foregroundStyle(.red)
			}
		case .canceled:
			Section {
				Label("Estimate canceled", systemImage: "slash.circle")
					.foregroundStyle(.secondary)
			}
		case .idle:
			EmptyView()
		}
	}

	// MARK: - Submit

	@ViewBuilder
	private var submitButton: some View {
		switch coordinator.state {
		case .running:
			Button("Cancel Estimate", role: .destructive) {
				coordinator.cancel()
			}
		default:
			Button("Run") {
				coordinator.acknowledge() // clear any prior terminal state first
				coordinator.start(parameters)
			}
			.disabled(!parameters.isValid)
		}
	}

	private var validationMessage: String? {
		guard !parameters.isValid else { return nil }
		return parameters.validationErrors().first?.localizedDescription
	}
}

// MARK: - Locale-aware length/range fields (Design Standards §10)

/// An editable length field (meters underneath) that displays and edits in the user's
/// locale unit. `Measurement<UnitLength>.FormatStyle` isn't `ParseableFormatStyle`, so
/// `TextField(value:format:)` can't bind to a `Measurement` directly for editing — the
/// unit conversion is done by hand instead, on a plain `Double` in the display unit.
private struct LengthField: View {
	let title: String
	@Binding var meters: Double

	private var unit: UnitLength { Locale.current.measurementSystem == .metric ? .meters : .feet }

	private var displayValue: Binding<Double> {
		Binding(
			get: { Measurement(value: meters, unit: UnitLength.meters).converted(to: unit).value },
			set: { meters = Measurement(value: $0, unit: unit).converted(to: .meters).value }
		)
	}

	var body: some View {
		HStack {
			Text(title)
			Spacer()
			TextField(title, value: displayValue, format: .number.precision(.fractionLength(0...1)))
				.multilineTextAlignment(.trailing)
				.keyboardType(.decimalPad)
			Text(unit.symbol).foregroundStyle(.secondary)
		}
	}
}

/// An editable range field (kilometers underneath) that displays and edits in the user's
/// locale unit, capped per contracts/query-contract.md (150 km, or 70 km with high-res
/// terrain) — the cap is expressed in km regardless of what unit is shown, since that's
/// the unit the underlying `maxRangeKm` and the query contract both use.
private struct RangeField: View {
	let title: String
	@Binding var kilometers: Double
	let highResolution: Bool

	private var unit: UnitLength { Locale.current.measurementSystem == .metric ? .kilometers : .miles }

	private var displayValue: Binding<Double> {
		Binding(
			get: { Measurement(value: kilometers, unit: UnitLength.kilometers).converted(to: unit).value },
			set: { kilometers = Measurement(value: $0, unit: unit).converted(to: .kilometers).value }
		)
	}

	var body: some View {
		HStack {
			Text(title)
			Spacer()
			TextField(title, value: displayValue, format: .number.precision(.fractionLength(0...1)))
				.multilineTextAlignment(.trailing)
				.keyboardType(.decimalPad)
			Text(unit.symbol).foregroundStyle(.secondary)
		}
	}
}
