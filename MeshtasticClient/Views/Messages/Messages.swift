import SwiftUI
import MapKit
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
    
    // Message Data and Bluetooth
    @EnvironmentObject var messageData: MessageData
    @EnvironmentObject var bleManager: BLEManager
    
    public var broadcastNodeId: UInt32 = 4294967295
    
    var body: some View {
        
        GeometryReader { bounds in
            
            VStack {
                
                ScrollViewReader { scrollView in
                    
                    ScrollView {
                        
                        Text("Hidden Top Anchor").hidden().frame(height: 0).id(topId)
                        
                        ForEach(messageData.messages.sorted(by: { $0.messageTimestamp < $1.messageTimestamp })) { message in
                            
                            MessageBubble(contentMessage: message.messagePayload, isCurrentUser: false, time: Int32(message.messageTimestamp), shortName: message.fromUserShortName)
                        }
                        .onAppear(perform: { scrollView.scrollTo(bottomId) } )
                        
                        Text("Hidden Bottom Anchor").hidden().frame(height: 0).id(bottomId)
                    }
                    .padding(.horizontal)
                }
                
                HStack (alignment: .top) {
                    
                    ZStack {
                
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
                            .keyboardType(.default)
                            .padding(.horizontal, 8)
                            .focused($focusedField, equals: .messageText)
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: bounds.size.height / 4, maxHeight: bounds.size.height / 4)
                           
                        Text(typingMessage).opacity(0).padding(.all, 0)
                        
                    }
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.tertiary, lineWidth: 1))
                    .padding(.bottom, 15)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill").font(.largeTitle).foregroundColor(.blue)
                    }
                    
                }
                .padding(.all, 15)
                HStack (alignment: .top ) {
                    
                    if focusedField != nil {
                        Button("Dismiss Keyboard") {
                            focusedField = nil
                        }
                        .font(.subheadline)
                        Spacer()
                        ProgressView("Bytes: \(totalBytes) / 200", value: Double(totalBytes), total: 200)
                            .frame(width: 130)
                            .padding(.bottom, 7)
                            .font(.subheadline)
                            .accentColor(Color.blue)
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("Channel - Primary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing:
                              
            ZStack {

                ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedNode != nil) ? bleManager.connectedNode.user.longName : ((bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.name : "Unknown") ?? "Unknown")
            }
        )
        .onAppear {
            messageData.load()
        }
    }
}
func sendMessage() {
        //chatHelper.sendMessage(Message(content: typingMessage, user: DataSource.secondUser))
       // typingMessage = ""
    }
