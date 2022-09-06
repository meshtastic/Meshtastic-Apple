import Foundation
import SwiftUI

struct NodeAnnotation: View {
	let time: Date
	
	let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())

	var body: some View {
		
		if (time >= sixMonthsAgo!) {
			
			VStack(spacing: 0) {
					Text(time, style: .offset)
						.font(.caption2).foregroundColor(.accentColor)
					.padding(5)
					.background(Color(.white))
					.cornerRadius(10)
			}
			
		} else {
				
			VStack(spacing: 0) {
				Text("Unknown Time")
					.font(.caption2).foregroundColor(.accentColor)
				.padding(5)
				.background(Color(.white))
				.cornerRadius(10)
			}
		}

		Image(systemName: "mappin.circle.fill")
			.font(.largeTitle)
			.foregroundColor(.accentColor)

		Image(systemName: "arrowtriangle.down.fill")
			.font(.caption)
			.foregroundColor(.accentColor)
			.offset(x: 0, y: -5)
	}
}
