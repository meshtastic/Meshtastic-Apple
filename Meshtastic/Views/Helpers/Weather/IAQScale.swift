//
//  IAQScale.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 4/24/24.
//

import SwiftUI

struct IAQScale: View {

	var body: some View {
		VStack(alignment: .leading) {
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
		.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 20)
				.stroke(.secondary, lineWidth: 5)
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
