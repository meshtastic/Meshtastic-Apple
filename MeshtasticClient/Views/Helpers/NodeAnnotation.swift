import Foundation
import SwiftUI

struct NodeAnnotation: View {
	let time: Date

	var body: some View {
		
		VStack(spacing: 0) {
			Text(time, style: .offset)
				.font(.callout).foregroundColor(.accentColor)
			.padding(5)
			.background(Color(.white))
			.cornerRadius(10)

		Image(systemName: "mappin.circle.fill")
			.font(.largeTitle)
			.foregroundColor(.accentColor)

		Image(systemName: "arrowtriangle.down.fill")
			.font(.caption)
			.foregroundColor(.accentColor)
			.offset(x: 0, y: -5)
		}
	}
}
