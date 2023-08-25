/*
Abstract:
A view draws a circle in the background of the shortName text
*/

import SwiftUI

struct CircleText: View {
    var text: String
    var color: Color
	var circleSize: CGFloat? = 60
	var fontSize: CGFloat? = 20
	var brightness: Double? = 0
	var textColor: Color? = .white

    var body: some View {

		let font = Font.system(size: fontSize!)

        ZStack {
            Circle()
                .fill(color)
				.brightness(brightness ?? 0)
                .frame(width: circleSize, height: circleSize)
			Text(text).textCase(.uppercase).font(font).foregroundColor(textColor).fixedSize()
                .frame(width: circleSize, height: circleSize, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/).offset(x: 0, y: 0)
        }
    }
}

struct CircleText_Previews: PreviewProvider {
    static var previews: some View {
		CircleText(text: "MOMO", color: Color.accentColor)
            .previewLayout(.fixed(width: 300, height: 100))
    }
}
