import SwiftUI

struct TapbackResponses: View {
	let tapbacks: [MessageEntity]

	@ViewBuilder
	var body: some View {
		if !tapbacks.isEmpty {
			VStack(alignment: .trailing) {
				HStack {
					ForEach(tapbacks) { (tapback: MessageEntity) in
						VStack {
							Text(tapback.messagePayload ?? "")
								.font(.system(size: 20))
								.lineLimit(1)
								.fixedSize()
							Text("\(tapback.fromUser?.shortName ?? "?")")
								.font(.caption2)
								.foregroundColor(.gray)
								.fixedSize()
								.padding(.bottom, 1)
						}
					}
				}
				.padding(10)
				.overlay(
					RoundedRectangle(cornerRadius: 18)
						.stroke(Color.gray, lineWidth: 1)
				)
			}
		}
	}
}
