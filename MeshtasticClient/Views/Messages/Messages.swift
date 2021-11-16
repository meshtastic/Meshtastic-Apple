import SwiftUI
import MapKit
import Foundation
import CoreLocation

struct Messages: View {
    
    enum Field: Hashable {
        case messageText
    }
    
    // Keyboard State
	@State var typingMessage: String = ""
    @State private var totalBytes = 0
    @State private var lastTypingMessage = ""
    @FocusState private var focusedField: Field?
	
    @Namespace var topId
    @Namespace var bottomId
	
	@State var showDeleteMessageAlert = false
	@State private var deleteMessageId : UInt32 = 0
    
    // Message Data and Bluetooth
    @EnvironmentObject var bleManager: BLEManager
    
    public var broadcastNodeId: UInt32 = 4294967295
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var messageCount: Int = 0;
    
    var body: some View {
		
		Text("\(messageCount) Messages").font(.caption)
        GeometryReader { bounds in
            
            VStack {
                
                ScrollViewReader { scrollView in
                    
					if self.bleManager.messageData.messages.count > 0 {
						
						ScrollView {
							
							Text("Hidden Top Anchor").hidden().frame(height: 0).id(topId)
							
							ForEach(bleManager.messageData.messages.sorted(by: { $0.messageTimestamp < $1.messageTimestamp })) { message in
								
								HStack (alignment: .top) {
									let currentUser: Bool = (bleManager.connectedNode != nil) && ((bleManager.connectedNode.id) == message.fromUserId)
									
									CircleText(text: message.fromUserShortName, color: currentUser ? .accentColor : Color(.darkGray)).padding(.all, 5)
										.gesture(LongPressGesture(minimumDuration: 2)
													.onEnded {_ in
											print("I want to delete message: \(message.messageId)")
											self.showDeleteMessageAlert = true
											self.deleteMessageId = message.messageId
											
										})
									
									
									VStack (alignment: .leading) {
										Text(message.messagePayload)
										.textSelection(.enabled)
										.padding(10)
										.foregroundColor(.white)
										.background(currentUser ? Color.blue : Color(.darkGray))
										.cornerRadius(10)
										HStack (spacing: 4) {
											
											let time = Int32(message.messageTimestamp)
											let messageDate = Date(timeIntervalSince1970: TimeInterval(time))

											if time != 0 {
												Text(messageDate, style: .date).font(.caption2).foregroundColor(.gray)
												Text(messageDate, style: .time).font(.caption2).foregroundColor(.gray)
											}
											else {
												Text("Unknown").font(.caption2).foregroundColor(.gray)
											}
										}
										.padding(.bottom, 10)
									}
									Spacer()
								}
								.alert(isPresented: $showDeleteMessageAlert) {
									Alert(title: Text("Are you sure you want to delete this message?"), message: Text("This action is permanent."),
										primaryButton: .destructive (Text("Delete")) {
										print("OK button tapped")
										if deleteMessageId > 0 {
											
											let messageIndex = bleManager.messageData.messages.firstIndex(where: { $0.messageId == deleteMessageId })
											bleManager.messageData.messages.remove(at: messageIndex!)
											bleManager.messageData.save()
											print("Deleted message: \(message.messageId)")
											showDeleteMessageAlert = false
											deleteMessageId = 0
										}
									},
									secondaryButton: .cancel()
									)
								}
							}
							.onAppear(perform: { scrollView.scrollTo(bottomId) } )
							Text("Hidden Bottom Anchor").hidden().frame(height: 0).id(bottomId)
						}
						.onReceive(timer) { input in
							
							if messageCount < bleManager.messageData.messages.count {
								
								bleManager.messageData.load()
								scrollView.scrollTo(bottomId)
								messageCount = bleManager.messageData.messages.count
							}
						}
						.padding(.horizontal)
					}
                }
                
                HStack (alignment: .top) {
                    
                    ZStack {

						let kbType = UIKeyboardType(rawValue: UserDefaults.standard.object(forKey: "keyboardType") as? Int ?? 0)
						TextEditor(text: $typingMessage)
                            .onChange(of: typingMessage, perform: { value in

                                let size = value.utf8.count
                                totalBytes = size
                                if totalBytes <= 200 {
                                    // Allow the user to type
                                    lastTypingMessage = typingMessage
                                }
                                else {
                                    // Set the message back and remove the bytes over the count
                                    self.typingMessage = lastTypingMessage
                                }
                            })
							.keyboardType(kbType!)
                            .toolbar
                            {
                                ToolbarItemGroup(placement: .keyboard) {
                                    
                                    Button("Dismiss Keyboard") {
                                        focusedField = nil
                                    }
                                    .font(.subheadline)
                                    
                                    Spacer()
                                    
                                    ProgressView("Bytes: \(totalBytes) / 200", value: Double(totalBytes), total: 200)
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
                        }
                        else {
                            
                            let _ = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { (timer) in
                            
                                if bleManager.sendMessage(message: typingMessage) {
                                    typingMessage = ""
                                }
                            }
                        }
                        
                    } ) {
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
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedNode != nil) ? bleManager.connectedNode.user.shortName : ((bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.name : "Unknown") )
		})
        .onAppear {
            
			messageCount = bleManager.messageData.messages.count
        }
    }
}
