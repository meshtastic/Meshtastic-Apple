import SwiftUI
import MapKit
import Foundation
import CoreLocation

struct Messages: View {

    enum Field: Hashable {
        case messageText
    }
	
	// CoreData
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(keyPath: \MessageEntity.messageTimestamp, ascending: true)],
		animation: .default)
	private var messages: FetchedResults<MessageEntity>

    // Keyboard State
	@State var typingMessage: String = ""
    @State private var totalBytes = 0
	private var maxbytes = 228
    @State private var lastTypingMessage = ""
    @FocusState private var focusedField: Field?

	@State var showDeleteMessageAlert = false
	@State private var deleteMessageId: Int64 = 0

    public var broadcastNodeId: UInt32 = 4294967295
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var messageCount: Int = 0

    var body: some View {

		Text("\(messageCount) Messages").font(.caption)
        GeometryReader { bounds in

            VStack {

                ScrollViewReader { scrollView in

					if self.messages.count > 0 {

						ScrollView {

							ForEach(messages) { message in

								HStack(alignment: .top) {
									//let currentUser: true//(message.fromUser != nil && bleManager.connectedPeripheral.num == message.fromUser!.num)
									

									CircleText(text: (message.fromUser?.longName ?? "???"), color: true ? .accentColor : Color(.darkGray)).padding(.all, 5)
										.gesture(LongPressGesture(minimumDuration: 2)
													.onEnded {_ in
											print("I want to delete message: \(message.messageId)")
											self.showDeleteMessageAlert = true
											self.deleteMessageId = message.messageId
											
											print(deleteMessageId)
										})

									VStack(alignment: .leading) {
										Text(message.messagePayload ?? "EMPTY MESSAGE")
										.textSelection(.enabled)
										.padding(10)
										.foregroundColor(.white)
										.background(true ? Color.blue : Color(.darkGray))
										.cornerRadius(10)
										HStack(spacing: 4) {

											let time = Int32(message.messageTimestamp)
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
								.alert(isPresented: $showDeleteMessageAlert) {
									Alert(title: Text("Are you sure you want to delete this message?"), message: Text("This action is permanent."),
										primaryButton: .destructive(Text("Delete")) {
										print("OK button tapped")
										if deleteMessageId > 0 {

											let message = messages.first(where: { $0.messageId == deleteMessageId })
											
											context.delete(message!)
											do {
												
												try context.save()
												deleteMessageId = 0
												messageCount = messages.count
												
											} catch {
												print("Failed to delete message \(deleteMessageId)")
											}
											
										}
									},
									secondaryButton: .cancel()
									)
								}
							}
							.onAppear(perform: {

								self.bleManager.context = context
								messageCount = messages.count
								if messageCount > 0 {
									scrollView.scrollTo(messages[messageCount-1].id, anchor: .bottom)
								}
								
							})
						}
						.onReceive(timer) { _ in

							if messageCount < messages.count {

								scrollView.scrollTo(messages[messageCount].id, anchor: .bottom)
								messageCount = messages.count

							}
						}
						.padding(.horizontal)
					}
                }

                HStack(alignment: .top) {

                    ZStack {

						let kbType = UIKeyboardType(rawValue: UserDefaults.standard.object(forKey: "keyboardType") as? Int ?? 0)
						TextEditor(text: $typingMessage)
                            .onChange(of: typingMessage, perform: { value in

                                let size = value.utf8.count
                                totalBytes = size
                                if totalBytes <= maxbytes {
                                    // Allow the user to type
                                    lastTypingMessage = typingMessage
                                } else {
                                    // Set the message back and remove the bytes over the count
                                    self.typingMessage = lastTypingMessage
                                }
                            })
							.keyboardType(kbType!)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {

                                    Button("Dismiss Keyboard") {
                                        focusedField = nil
                                    }
                                    .font(.subheadline)

                                    Spacer()

                                    ProgressView("Bytes: \(totalBytes) / \(maxbytes)", value: Double(totalBytes), total: Double(maxbytes))
                                        .frame(width: 130)
                                        .padding(5)
                                        .font(.subheadline)
										.accentColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 8)
                            .focused($focusedField, equals: .messageText)
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: bounds.size.height / 4, maxHeight: bounds.size.height / 4)

                        Text(typingMessage).opacity(0).padding(.all, 0)

                    }
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.tertiary, lineWidth: 1))
                    .padding(.bottom, 15)

                    Button(action: {
                        if bleManager.sendMessage(message: typingMessage) {
                            typingMessage = ""
                        } else {

                            _ = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { (_) in

                                if bleManager.sendMessage(message: typingMessage) {
                                    typingMessage = ""
                                }
                            }
                        }

                    }) {
                        Image(systemName: "arrow.up.circle.fill").font(.largeTitle).foregroundColor(.blue)
                    }

                }
                .padding(.all, 15)
            }
        }
        .navigationTitle("Channel - Primary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing:

		ZStack {

			ConnectedDevice(
				bluetoothOn: bleManager.isSwitchedOn,
				deviceConnected: bleManager.connectedPeripheral != nil,
				name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName :
					"???")
		})
		.onAppear(perform: {

			self.bleManager.context = context
			messageCount = messages.count
		})
    }
}
