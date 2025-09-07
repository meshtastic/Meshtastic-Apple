/*
Abstract:
A view draws a circle in the background of the shortName text
*/

import SwiftUI
import CoreData

struct CircleText: View {
	var text: String
	var color: Color
	var circleSize: CGFloat = 45
	var node: NodeInfoEntity?

	var body: some View {
			if let node = node {
					NavigationLink(destination: NodeDetail(node: node)) {
						circleContent
					}
			} else {
				circleContent
		}
	}

	var circleContent: some View {
		ZStack {
			Circle()
				.fill(color)
				.frame(width: circleSize, height: circleSize)
			Text(text)
				.frame(width: circleSize * 0.9, height: circleSize * 0.9, alignment: .center)
				.foregroundColor(color.isLight() ? .black : .white)
				.minimumScaleFactor(0.001)
				.font(.system(size: 1300))
		}
	}
}

struct CircleText_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
			HStack {
				CircleText(text: "N1", color: Color.yellow, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "8", color: Color.purple, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "😝", color: Color.red, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "🍔", color: Color.brown, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}
			HStack {
				CircleText(text: "👻", color: Color.orange, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "🤙", color: Color.orange, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "69", color: Color.green, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "WWWW", color: Color.cyan, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}
			HStack {

				CircleText(text: "CW-A", color: Color.secondary)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "CW-A", color: Color.secondary, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "MOMO", color: Color.mint, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "IIII", color: Color.accentColor, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}
			HStack {

				CircleText(text: "🚗", color: Color.orange)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "🔋", color: Color.indigo, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "🛢️", color: Color.orange, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "LCP", color: Color.indigo, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}
			HStack {
				CircleText(text: "🤡", color: Color.red, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}
		}
	}
}
