import SwiftUI
import MapKit
import CoreLocation

struct MessageDetail: View {
    
    @State var typingMessage: String = ""
    
    var body: some View {
       // NavigationView {
           
            VStack(alignment: .leading) {
                ScrollView {
                    
                    MessageBubble(contentMessage: "I sent a super great message with amazing text", isCurrentUser: true, time: 1, shortName: "GVH")
                    MessageBubble(contentMessage: "It was amazing to read such a fantastical text", isCurrentUser: false, time: 1, shortName: "RS1")
                    MessageBubble(contentMessage: "It was the best message", isCurrentUser: false, time: 1, shortName: "RDN")
                    MessageBubble(contentMessage: "This is a terse response to an amazing text", isCurrentUser: true, time: 1, shortName: "GVH")
                    MessageBubble(contentMessage: "yo", isCurrentUser: true, time: 1, shortName: "GVH")
                    MessageBubble(contentMessage: "I sent a super great message with amazing text", isCurrentUser: true, time: 1, shortName: "GVH")
                    MessageBubble(contentMessage: "It was amazing to read such a fantastical text", isCurrentUser: false, time: 1, shortName: "RS1")
                    MessageBubble(contentMessage: "It was the best message", isCurrentUser: false, time: 1, shortName: "RDN")
                    MessageBubble(contentMessage: "This is a terse response to an amazing text", isCurrentUser: true, time: 1, shortName: "GVH")
                    MessageBubble(contentMessage: "yo", isCurrentUser: true, time: 1, shortName: "GVH")
                    
                    
                    
                    
                }.padding([.top, .leading])
                HStack (alignment: .bottom) {
                    
                       TextField("Message", text: $typingMessage)
                          .textFieldStyle(RoundedBorderTextFieldStyle())
                          .frame(minHeight: CGFloat(30))
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill").font(.title).foregroundColor(.blue)
                        }
                }.padding(5)
            }
            .navigationTitle("CHANNEL - Primary")
            .navigationBarTitleDisplayMode(.inline)
        //}
        //.navigationViewStyle//(StackNavigationViewStyle())
    }
}
