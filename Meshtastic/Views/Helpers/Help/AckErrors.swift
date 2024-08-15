//
//  IAQScale.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 4/24/24.
//

import SwiftUI

struct AckErrors: View {

	var body: some View {
		VStack(alignment: .leading) {
			Text("Message Status Options")
				.font(.title2)
			HStack {
				RoundedRectangle(cornerRadius: 5)
					.fill(.orange)
					.frame(width: 20, height: 12)
				Text("Acknowledged by another node")
					.font(.caption)
					.foregroundStyle(.orange)
			}
			ForEach(RoutingError.allCases) { re in
				HStack {
					RoundedRectangle(cornerRadius: 5)
						.fill(re.color)
						.frame(width: 20, height: 12)
					Text(re.display)
						.font(.caption)
						.foregroundStyle(re.color)
				}
			}
		}
	}
}

struct AckErrorsPreviews: PreviewProvider {
	static var previews: some View {
		VStack {
			AckErrors()
		}
	}
}
