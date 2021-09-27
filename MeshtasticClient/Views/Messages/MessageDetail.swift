import SwiftUI
import MapKit
import CoreLocation

struct MessageDetail: View {
    
    enum Field: Hashable {
        case messageText
    }
    
    @State var typingMessage: String = ""
    @FocusState private var focusedField: Field?
    @ObservedObject var messageData: MessageData = MessageData()
    @EnvironmentObject var bleManager: BLEManager
    
    @Namespace var topId
    @Namespace var bottomId
    
    var body: some View {
        
        GeometryReader { bounds in
            
            VStack {
                
                ScrollViewReader { scrollView in
                    
                    ScrollView {
                        Text("Hidden Top Anchor")
                            .hidden()
                            .frame(height: 0)
                            .id(topId)
                        
                        ForEach(messageData.messages.sorted(by: { $0.messageTimestamp < $1.messageTimestamp })) { message in
                            
                            MessageBubble(contentMessage: message.messagePayload, isCurrentUser: false, time: Int32(message.messageTimestamp), shortName: message.fromUserShortName)
                        }
                        .onAppear(perform: { scrollView.scrollTo(bottomId) } )
                        
                        Text("Hidden Bottom Anchor")
                            .hidden()
                            .frame(height: 0)
                            .id(bottomId)
                    }
                    .padding([.top, .leading])
                }
                HStack {
                    
                    if focusedField != nil {
                        Button("Dismiss Keyboard") {
                            focusedField = nil
                        }
                        .fixedSize()
                        .frame(height: 15, alignment: .center)
                        .padding(.top, 10)
                    }
                }
                HStack (alignment: .top) {
                
                    ZStack {
                    
                        TextEditor(text: $typingMessage)
                            .onChange(of: typingMessage, perform: { value in
                                let size = value.utf8.count
                                if size >= 200 {
                                    print("too big!")
                                }
                                print(size)
                            })
                            .padding(.horizontal)
                            .focused($focusedField, equals: .messageText)
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 120, maxHeight: 120)
                        
                           
                        Text(typingMessage).opacity(0).padding(.all, 2)
                        
                    }
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.tertiary, lineWidth: 2))
                    .padding(.top)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill").font(.largeTitle).foregroundColor(.blue)
                    }
                    .padding(.top)
                    
                }.padding([.leading, .bottom])
            }
        }
        .navigationTitle("CHANNEL - Primary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing:
                              
            ZStack {

                ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedNode != nil) ? bleManager.connectedNode.user.longName : ((bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.name : "Unknown") ?? "Unknown")
            
            }
        )
        .onAppear{
            messageData.load()
        }
    }
}
