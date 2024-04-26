//
//  IAQScale.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 4/24/24.
//

import SwiftUI

struct IAQScale: View {

	var body: some View {
		VStack(alignment:.leading) {
			ForEach(Iaq.allCases) { iaq in
				HStack {
					RoundedRectangle(cornerRadius: 5)
						.fill(iaq.color)
						.frame(width: 30, height: 20)
					Text(iaq.description)
						.font(.callout)
				}
			}
		}
		.padding()
		.background(.white)
		.cornerRadius(20) /// make the background rounded
		.overlay(
			RoundedRectangle(cornerRadius: 20)
				.stroke(.secondary, lineWidth: 4)
		)
	}
}

struct IAQSCalePreviews: PreviewProvider {
	static var previews: some View {
		VStack {
			IAQScale()
		}
	}
}
