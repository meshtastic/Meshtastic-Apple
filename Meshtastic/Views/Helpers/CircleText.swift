/*
Abstract:
A view draws a circle in the background of the shortName text
*/

import SwiftUI

struct CircleText: View {
    var text: String
    var color: Color
	var circleSize: CGFloat = 45
	var textColor: Color? = .white
	
    var body: some View {

        ZStack {
            Circle()
                .fill(color)
                .frame(width: circleSize, height: circleSize)
			Text(text)
				.textCase(.uppercase)
				.foregroundColor(textColor)
				.font(.system(size: 500))
					  .minimumScaleFactor(0.001)
					  .frame(width: circleSize * 0.90,
							 height: circleSize * 0.90, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
        }
    }
}

struct CircleText_Previews: PreviewProvider {
    static var previews: some View {
		CircleText(text: "MOMO", color: Color.accentColor, circleSize: 80)
		CircleText(text: "WWWW", color: Color.accentColor, circleSize: 80)
		CircleText(text: "LCP", color: Color.accentColor, circleSize: 80)
		CircleText(text: "8", color: Color.accentColor, circleSize: 80)
            .previewLayout(.fixed(width: 300, height: 100))
    }
}
