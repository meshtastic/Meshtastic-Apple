import SwiftUI

struct MessageBubble: View {
    var contentMessage: String
    var isCurrentUser: Bool
    var time: Int32
    var shortName: String
    
    var body: some View {
        HStack (alignment: .top) {
            
            CircleText(text: shortName, color: isCurrentUser ? Color.blue : Color(.darkGray)).padding(.all, 5)
            VStack (alignment: .leading) {
            Text(contentMessage)
                .textSelection(.enabled)
                .padding(10)
                .foregroundColor(.white)
                .background(isCurrentUser ? Color.blue : Color(.darkGray))
                .cornerRadius(10)
                HStack (spacing: 4) {
                    let messageDate = Date(timeIntervalSince1970: TimeInterval(time))

                    Text(messageDate, style: .date).font(.caption2).foregroundColor(.gray)
                    Text(messageDate, style: .time).font(.caption2).foregroundColor(.gray)
                }
                .padding(.bottom, 10)
            }
            Spacer()
        }
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


