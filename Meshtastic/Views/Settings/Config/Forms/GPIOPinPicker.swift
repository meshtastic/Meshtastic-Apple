//
//  GPIOPinPicker.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI

/// The pin picker every GPIO setting uses: 0 is "Unset", 1-48 are pins.
///
/// Fourteen config screens carried this same `ForEach(0..<49)` by hand. The range is
/// the app's, not the firmware's - boards differ - which is why it is a control here
/// and not a bound in the schema.
struct GPIOPinPicker: View {
	let title: String
	@Binding var selection: Int

	var body: some View {
		// The label wraps and the pin stays on the right. A plain Picker drops its value onto
		// a line of its own once the label is too long to fit beside it, which the registry's
		// longer names (such as "Transmit data (txd) GPIO pin") are on a phone.
		HStack {
			Text(title)
			Spacer(minLength: 8)
			Picker(title, selection: $selection) {
				ForEach(0..<49, id: \.self) { pin in
					if pin == 0 {
						Text("Unset").tag(pin)
					} else {
						Text("Pin \(pin)").tag(pin)
					}
				}
			}
			.labelsHidden()
			.fixedSize()
			// The menu button is taller than a line of text; without this the description
			// sits lower under these rows than under the form's other pickers.
			.padding(.vertical, -8)
		}
	}
}
