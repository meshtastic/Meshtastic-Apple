import SwiftUI

struct TapbackResponses: View {
	@Environment(\.managedObjectContext) var context
	
	let message: MessageEntity
	let onRead: () ->  Void

	@ViewBuilder
	var body: some View {
		let tapbacks = message.value(forKey: "tapbacks") as? [MessageEntity] ?? []
		if !tapbacks.isEmpty {
			VStack(alignment: .trailing) {
				HStack {
					ForEach( tapbacks ) { (tapback: MessageEntity) in
						VStack {
							let image = tapback.messagePayload!.image(fontSize: 20)
							Image(uiImage: image!).font(.caption)
							Text("\(tapback.fromUser?.shortName ?? "?")")
								.font(.caption2)
								.foregroundColor(.gray)
								.fixedSize()
								.padding(.bottom, 1)
						}
						.onAppear {
							guard !tapback.read else {
								return
							}

							tapback.read = true
							do {
								try context.save()
								print("📖 Read tapback \(tapback.messageId) ")
								onRead()
							} catch {
								print("Failed to read tapback \(tapback.messageId)")
							}
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
