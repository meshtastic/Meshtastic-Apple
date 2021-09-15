/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view that clips an image to a circle and adds a stroke and shadow.
*/

import SwiftUI

struct CircleText: View {
    var text: String

    var body: some View {
        
        Text(text).font(.subheadline).foregroundColor(.white)
            .background(Circle()
            .fill(Color.blue)
            .frame(width: 40, height: 40, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/))
    }
}

struct CircleText_Previews: PreviewProvider {
    static var previews: some View {
        CircleText(text: "RDN")
    }
}
