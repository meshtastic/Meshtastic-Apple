/*
Abstract:
A view draws a circle in the background of the shortName text
*/

import SwiftUI

struct CircleText: View {
    var text: String
    var color: Color
	var circleSize: CGFloat? = 45
	var textColor: Color? = .white
	
    var body: some View {

		let font = Font.system(size: (text.count == 1) ? ((circleSize ?? 45) * 0.75) : (text.count == 2 ? ((circleSize ?? 45) * 0.52) : (text.count == 3 ? ((circleSize ?? 45) * 0.42) : ((circleSize ?? 45) * 0.32))))

        ZStack {
            Circle()
                .fill(color)
                .frame(width: circleSize, height: circleSize)
			Text(text)
				.textCase(.uppercase)
				.font(font)
				.foregroundColor(textColor)
				.fixedSize()
                .frame(width: circleSize, height: circleSize, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
        }
    }
}

struct CircleText_Previews: PreviewProvider {
    static var previews: some View {
		CircleText(text: "MOMO", color: Color.accentColor, circleSize: 80)
            .previewLayout(.fixed(width: 300, height: 100))
    }
}
