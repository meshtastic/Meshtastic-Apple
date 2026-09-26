//
//  UpdateIntervalPicker.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/4/25.
//
import SwiftUI

struct UpdateIntervalPicker: View {
	let config: IntervalConfiguration
	// LocalizedStringKey, not String: a String argument binds Picker's non-localizing
	// StringProtocol overload, so these 19 labels were never extracted for translation.
	let pickerLabel: LocalizedStringKey
	let formatter: DateComponentsFormatter // Make it a stored property
	
	@Binding var selectedInterval: UpdateInterval
	
	private var fixedOptions: [UpdateInterval] {
		config.allowedCases
			.map { UpdateInterval(from: $0.rawValue) }
	}
	
	init(config: IntervalConfiguration, pickerLabel: LocalizedStringKey, selectedInterval: Binding<UpdateInterval>) {
		self.config = config
		self.pickerLabel = pickerLabel
		self._selectedInterval = selectedInterval
		let f = DateComponentsFormatter()
		f.unitsStyle = .full
		self.formatter = f
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Picker(pickerLabel, selection: $selectedInterval) {
				ForEach(fixedOptions, id: \.self) { interval in
					Text(interval.description)
						.tag(interval)
				}
			}
			
			if isOutOfRange {
				let interval: TimeInterval = Double(selectedInterval.intValue)
				if let formattedString = formatter.string(from: interval) {
					Text("⚠️ The configured value: (\(formattedString)) is not one of the optimized options.")
						.font(.caption)
						.foregroundColor(.orange)
				}
			}
		}
	}
	private var isOutOfRange: Bool {
		switch selectedInterval.type {
		case .manual:
			return true
		case .fixed(let fixedCase):
			return !config.allowedCases.contains(fixedCase)
		}
	}
}

#Preview {
	UpdateIntervalPicker(
		config: .broadcastShort,
		pickerLabel: "Update Interval",
		selectedInterval: .constant(UpdateInterval(from: 30))
	)
}
