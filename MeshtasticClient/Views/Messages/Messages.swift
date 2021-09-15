import SwiftUI
import MapKit
import CoreLocation

struct Messages: View {
    var body: some View {
        NavigationView {
           
            List {
                HStack {
                    Text("RGN").font(.subheadline).foregroundColor(.white).background(Circle().fill(Color.blue).frame(width: 40, height: 40))
                    VStack(alignment: .trailing) {
                        Text("I sent a super great message with amazing text").padding().foregroundColor(.white).background(Capsule().fill(Color.green))
                        Text("8/7/21 8:39 PM").font(.subheadline).foregroundColor(.gray)
                    }
                    
                }
                VStack {
                    HStack {
                        Text("RGN").font(.subheadline).foregroundColor(.white).background(Circle().fill(Color.blue).frame(width: 40, height: 40))
                        HStack {
                            Text("I sent a super great message with amazing text").padding().foregroundColor(.white).background(Capsule().fill(Color.green))
                            Text("8/7/21 8:39 PM").font(.subheadline).foregroundColor(.gray)
                        }
                    }
                    HStack {
                        Text("8/7/21 8:39 PM").font(.subheadline).foregroundColor(.gray)
                    }

                }
                VStack {
                    HStack {
                        Text("RS1").font(.subheadline).foregroundColor(.white).background(Circle().fill(Color.blue).frame(width: 40, height: 40))
                        Text("the best message").padding().foregroundColor(.white).background(Capsule().fill(Color.green))
                    }
                    HStack {
                        Text("8/7/21 8:45 PM").font(.subheadline).foregroundColor(.gray)
                    }

                }
                VStack {
                    HStack{
                        Text("YB").font(.subheadline).foregroundColor(.white).background(Circle().fill(Color.green).frame(width: 40, height: 40))
                        Spacer(minLength: 50)
                        Text("This is a terse response to an amazing text").padding().foregroundColor(.white).background(Capsule().fill(Color.green))
                    }
                    HStack {
                        
                        Text("8/7/21 8:53 PM").font(.subheadline).foregroundColor(.gray)
                        Spacer()
                    }
                }
            }.navigationTitle("Broadcast Channel")
            .navigationBarTitleDisplayMode(.inline)
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
