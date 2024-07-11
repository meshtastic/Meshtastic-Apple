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
			Text("Indoor Air Quality (IAQ)")
				.font(.title3)
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
	}
}

struct IAQSCalePreviews: PreviewProvider {
	static var previews: some View {
		VStack {
			IAQScale()
		}
	}
}
