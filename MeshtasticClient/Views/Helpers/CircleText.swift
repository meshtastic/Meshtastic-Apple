/*
Abstract:
A view draws a circle in the background of the shortName text
*/

import SwiftUI

struct CircleText: View {
    var text: String
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
            Text(text).textCase(.uppercase).font(.caption2).foregroundColor(.white)
                .frame(width: 36, height: 36, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/).offset(x: 0, y: 0)
        }
    }
}

struct CircleText_Previews: PreviewProvider {
    static var previews: some View {
        CircleText(text: "RDN", color: Color.blue)
            .previewLayout(.fixed(width: 300, height: 100))
    }
}
