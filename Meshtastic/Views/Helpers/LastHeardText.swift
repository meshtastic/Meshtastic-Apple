import SwiftUI
//
//  LastHeardText.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/25/22.
//
struct LastHeardText: View {
	var lastHeard: Date?

	var body: some View {
		if let lastHeard, lastHeard.timeIntervalSince1970 > 0 {
			Text(lastHeard.formatted())
		} else {
			Text("unknown")
		}
	}
}
struct LastHeardText_Previews: PreviewProvider {
	static var previews: some View {
		LastHeardText(lastHeard: Date())
			.previewLayout(.fixed(width: 300, height: 100))
			.environment(\.locale, .init(identifier: "en"))
		LastHeardText(lastHeard: Date())
			.previewLayout(.fixed(width: 300, height: 100))
			.environment(\.locale, .init(identifier: "de"))
	}
}
