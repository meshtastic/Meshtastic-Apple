//
//  WaypointFormView.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 1/10/23.
//

import SwiftUI

struct WaypointFormView: View {
	
	@Environment(\.dismiss) private var dismiss
	@FocusState private var emojiIsFocused: Bool
	@State private var id: Int32?
	@State private var name: String = ""
	@State private var description: String = ""
	@State private var emoji: String = "📍"
	@State private var latitude: Double = 0.0
	@State private var longitude: Double = 0.0
	@State private var expire: Date = Date.now.addingTimeInterval(60 * 120) // 1 minute * 120 = 2 Hours
	@State private var locked: Bool = false

	var body: some View {

		Form {
			Section(header: Text("Waypoint").font(.title3)) {
				Text("Distance Away").foregroundColor(Color.gray)
				Text("Lat/Long ") + Text(" \(String(latitude) + "," + String(longitude))").foregroundColor(Color.gray)
				HStack {
					Text("Name")
					Spacer()
					TextField(
						"Name",
						text: $name
					)
					.foregroundColor(Color.gray)
					.onChange(of: name, perform: { value in
						let totalBytes = name.utf8.count
						// Only mess with the value if it is too big
						if totalBytes > 30 {
							let firstNBytes = Data(name.utf8.prefix(30))
							if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
								// Set the name back to the last place where it was the right size
								name = maxBytesString
							}
						}
					})
				}
				HStack {
					Text("Description")
					Spacer()
					TextField(
						"Description",
						text: $description,
						axis: .vertical
					)
					.foregroundColor(Color.gray)
					.onChange(of: description, perform: { value in
						let totalBytes = description.utf8.count
						// Only mess with the value if it is too big
						if totalBytes > 100 {
							let firstNBytes = Data(description.utf8.prefix(100))
							if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
								// Set the name back to the last place where it was the right size
								description = maxBytesString
							}
						}
					})
				}
				HStack {
					Text("Icon")
					Spacer()
					EmojiOnlyTextField(text: $emoji, placeholder: "Select an emoji")
						.font(.title)
						.focused($emojiIsFocused)
						.onChange(of: emoji) { value in
							
							// If you have anything other than emojis in your string make it empty
							if !value.onlyEmojis() {
								emoji = ""
							}
							// If a second emoji is entered delete the first one
							if value.count >= 1 {
								
								if value.count > 1 {
									let index = value.index(value.startIndex, offsetBy: 1)
									emoji = String(value[index])
								}
								emojiIsFocused = false
							}
						}
					
				}
				DatePicker("Expire", selection: $expire, in: Date.now...)
					.datePickerStyle(.compact)
					.font(.callout)
				Toggle(isOn: $locked) {
					Label("Locked", systemImage: "lock")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
			}
		}
		HStack {
			Button {
				dismiss()
			} label: {
				Label("save", systemImage: "square.and.arrow.down")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(5)
			
			Button {
				dismiss()
			} label: {
				Label("cancel", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(5)
		}
	}
}
