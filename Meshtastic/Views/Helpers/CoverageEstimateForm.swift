//
//  CoverageEstimateForm.swift
//  Meshtastic
//
//  The Site/Transmitter, Receiver, Simulation, and Display sections for a Site Planner
//  coverage estimate (spec 015, US1/US2). The Environment (advanced) section and the
//  situation/time-fraction fields are deferred to US3 (T023) — see data-model.md.
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
	@ObservedObject private var coordinator = CoverageEstimateCoordinator.shared
	@Environment(\.dismiss) private var dismiss

	init(initialParameters: CoverageEstimateParameters) {
		_parameters = State(initialValue: initialParameters)
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
		}
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
