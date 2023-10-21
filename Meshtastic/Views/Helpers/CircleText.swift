/*
Abstract:
A view draws a circle in the background of the shortName text
*/

import SwiftUI

struct CircleText: View {
    var text: String
    var color: Color
	var circleSize: CGFloat = 45
	
    var body: some View {

        ZStack {
            Circle()
                .fill(color)
                .frame(width: circleSize, height: circleSize)
			Text(text)
				.textCase(.uppercase)
				.foregroundColor(color.isLight() ? .black : .white)
				.font(.system(size: 8000))
					  .minimumScaleFactor(0.001)
					  .frame(width: circleSize * 0.95, height: circleSize * 0.95, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
        }
		.aspectRatio(1, contentMode: .fit)
    }
}

struct CircleText_Previews: PreviewProvider {
    static var previews: some View {
		
		HStack {
			VStack {

				CircleText(text: "N1", color: Color.yellow, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "8", color: Color.purple, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "😝", color: Color.red, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "🍔", color: Color.brown, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "👻", color: Color.orange, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "🤙", color: Color.orange, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				
			}
			VStack {
				CircleText(text: "69", color: Color.green, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "WWWW", color: Color.cyan, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "CW-A", color: Color.secondary)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "CW-A", color: Color.secondary, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "MOMO", color: Color.mint, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "IIII", color: Color.accentColor, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				CircleText(text: "LCP", color: Color.primary, circleSize: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}
		}
    }
}
