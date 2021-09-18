import SwiftUI

struct MessageBubble: View {
    var contentMessage: String
    var isCurrentUser: Bool
    var time: Int32
    var shortName: String
    
    var body: some View {
        VStack(alignment: isCurrentUser ? .leading : .trailing) {
            HStack {
                
                CircleText(text: shortName, color: isCurrentUser ? Color.blue : Color(.darkGray)).padding(.all, 5)
                
                Text(contentMessage)
                    .padding(10)
                    .foregroundColor(.white)
                    .background(isCurrentUser ? Color.blue : Color(.darkGray))
                    .cornerRadius(10)
                Spacer()
            }.padding(isCurrentUser ? .leading : .trailing, 70)
        }.padding(.bottom, 1)
    }
}

struct MessageBubble_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MessageBubble(contentMessage: "this is the best text ever", isCurrentUser: true, time: 0, shortName: "EB")
        }
        .previewLayout(.fixed(width: 300, height: 100))
    }
}


