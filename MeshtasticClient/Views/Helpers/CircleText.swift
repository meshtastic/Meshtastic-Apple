/*
Abstract:
A view draws a circle in the background of the shortName text
*/

import SwiftUI

struct CircleText: View {
    var text: String
    var color: Color
	var circleSize: CGFloat? = 40
	var fontSize: CGFloat? = 16

    var body: some View {
		
		let font = Font.system(size: fontSize!)
		
        ZStack {
            Circle()
                .fill(color)
                .frame(width: circleSize, height: circleSize)
			Text(text).textCase(.uppercase).font(font).foregroundColor(.white)
                .frame(width: circleSize, height: circleSize, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/).offset(x: 0, y: 0)
        }
    }
}

struct CircleText_Previews: PreviewProvider {
    static var previews: some View {
		CircleText(text: "RDN", color: Color.accentColor)
            .previewLayout(.fixed(width: 300, height: 100))
    }
}
