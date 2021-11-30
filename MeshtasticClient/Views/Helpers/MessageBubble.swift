import SwiftUI

struct MessageBubble: View {

	@State var showAlert = false
    var contentMessage: String
    var isCurrentUser: Bool
    var time: Int32
    var shortName: String
	var id: UInt32

    var body: some View {

        HStack(alignment: .top) {

            CircleText(text: shortName, color: isCurrentUser ? Color.blue : Color(.darkGray)).padding(.all, 5)
				.gesture(LongPressGesture(minimumDuration: 2)
							.onEnded {_ in
					 print("I want to delete message: \(id)")
					self.showAlert = true
				})

            VStack(alignment: .leading) {
            Text(contentMessage)
                .textSelection(.enabled)
                .padding(10)
                .foregroundColor(.white)
                .background(isCurrentUser ? Color.blue : Color(.darkGray))
                .cornerRadius(10)
                HStack(spacing: 4) {

                   let messageDate = Date(timeIntervalSince1970: TimeInterval(time))

                    if time != 0 {
                        Text(messageDate, style: .date).font(.caption2).foregroundColor(.gray)
                        Text(messageDate, style: .time).font(.caption2).foregroundColor(.gray)
                    } else {
                        Text("Unknown").font(.caption2).foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 10)
            }
            Spacer()
        }
		.alert(isPresented: $showAlert) {
			Alert(title: Text("Are you sure you want to delete this message?"), message: Text("This action is permanent."),
				  primaryButton: .destructive(Text("OK")) {
				  print("OK button tapped")
				// let messageIndex = meshData.nodes.firstIndex(where: { $0.id == node.id })
				// meshData.nodes.remove(at: nodeIndex!)
				// meshData.save()
			},
			secondaryButton: .cancel()
			)
		}
    }
}

struct MessageBubble_Previews: PreviewProvider {
    static var previews: some View {
        Group {
			MessageBubble(contentMessage: "this is the best text ever", isCurrentUser: true, time: 0, shortName: "EB", id: 12)
        }
        .previewLayout(.fixed(width: 300, height: 100))
    }
}
