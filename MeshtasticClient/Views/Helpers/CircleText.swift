/*
Abstract:
A view draws a circle in the background of the shortName text
*/

import SwiftUI

struct CircleText: View {
    var text: String
    var color: Color

    var body: some View {
        
        Text(text).font(.caption2).foregroundColor(.white)
            .background(Circle()
            .fill(color)
            .frame(width: 32, height: 32, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/))
    }
}

struct CircleText_Previews: PreviewProvider {
    static var previews: some View {
        CircleText(text: "RDN", color: Color.blue)
            .previewLayout(.fixed(width: 300, height: 100))
    }
}
