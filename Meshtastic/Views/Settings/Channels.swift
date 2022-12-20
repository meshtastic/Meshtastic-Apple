//
//  ShareChannel.swift
//  MeshtasticApple
//
//  Copyright(c) Garth Vander Houwen 4/8/22.
//
import SwiftUI
import CoreData

func generateChannelKey(size: Int) -> String {
	var keyData = Data(count: size)
	_ = keyData.withUnsafeMutableBytes {
	  SecRandomCopyBytes(kSecRandomDefault, size, $0.baseAddress!)
	}
	return keyData.base64EncodedString()
}

struct Channels: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var dismiss
	@Environment(\.sizeCategory) var sizeCategory

	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State private var isPresentingEditView = false
	@State private var selectedIndex: Int32 = -1
	
	@State private var channelIndex: Int32 = 0
	@State private var channelName = "Channel"
	@State private var channelKeySize = 32
	@State private var channelKey = "AQ=="
	@State private var channelRole = 2
	@State private var uplink = false
	@State private var downlink = false
	
	var body: some View {
		
		NavigationStack {
			List {
				if node != nil && node?.myInfo != nil {
					ForEach(node!.myInfo!.channels?.array as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in
						Button(action:  {
							selectedIndex = channel.index
							channelIndex = channel.index
							channelRole = Int(channel.role)
							channelKey = channel.psk?.hexDescription ?? ""
							isPresentingEditView = true
							channelName = channel.name ?? "Channel\(channelIndex)"
							uplink = channel.uplinkEnabled
							downlink = channel.downlinkEnabled
						}) {
							VStack(alignment: .leading) {
								HStack {
									CircleText(text: String(channel.index), color: .accentColor, circleSize: 45, fontSize: 36, brightness: 0.1)
										.padding(.trailing, 5)
									VStack {
										HStack {
											if channel.name?.isEmpty ?? false {
												if channel.role == 1 {
													Text(String("PrimaryChannel").camelCaseToWords()).font(.headline)
												} else {
													Text(String("Channel \(channel.index)").camelCaseToWords()).font(.headline)
												}
											} else {
												Text(String(channel.name ?? "Channel \(channel.index)").camelCaseToWords()).font(.headline)
											}
										}
									}
								}
							}
						}
					}
				}
			}
			if node?.myInfo?.channels?.array.count ?? 0 < 8 {
				
				Button {
					let key = generateChannelKey(size: 32)
					print("Add Channel Key \(key) ")
					isPresentingEditView = true
					channelIndex = Int32(node!.myInfo!.channels!.array.count)
					channelRole = 2
					channelName = "Channel\(channelIndex)"
					channelKey = key
					uplink = false
					downlink = false
					
				} label: {
					Label("Add Channel", systemImage: "plus.square")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.sheet(isPresented: $isPresentingEditView) {
					
					#if targetEnvironment(macCatalyst)
					Text("edit.channel")
						.font(.largeTitle)
						.padding()
					#endif
					Form {
						Section("Edit Channel \(channelIndex)") {
							HStack {
								Text("name")
								Spacer()
								TextField(
									"Channel Name",
									text: $channelName
								)
								.foregroundColor(Color.gray)
							}
							HStack {
								Picker("Key Size", selection: $channelKeySize) {
									Text("Empty").tag(0)
									Text("Default").tag(-1)
									Text("1 Bit").tag(1)
									Text("128 Bit").tag(16)
									Text("256 Bit").tag(32)
								}
								.pickerStyle(DefaultPickerStyle())
								Spacer()
								Button {
									if channelKeySize == -1 {
										channelKey = "AQ=="
									} else {
										let key = generateChannelKey(size: channelKeySize)
										channelKey = key.base64ToBase64url()
									}
								} label: {
									Image(systemName: "lock.rotation")
										.font(.title)
								}
								.buttonStyle(.bordered)
								.buttonBorderShape(.capsule)
								.controlSize(.small)
							}
							HStack (alignment: .top) {
								Text("Key")
								Spacer()
								TextField (
									"",
									text: $channelKey,
									axis: .vertical
								)
								.foregroundColor(Color.gray)

								.disabled(true)
							}
							Picker("Channel Role", selection: $channelRole) {
								if channelRole == 1 {
									Text("Primary").tag(1)
								} else{
									Text("Disabled").tag(0)
									Text("Secondary").tag(2)
								}
							}
							.pickerStyle(DefaultPickerStyle())
							Toggle("Uplink Enabled", isOn: $uplink)
								.toggleStyle(SwitchToggleStyle(tint: .accentColor))
							Toggle("Downlink Enabled", isOn: $downlink)
								.toggleStyle(SwitchToggleStyle(tint: .accentColor))
							
						}
						.onSubmit {
							//validate(name: channelName)
						}
						.onChange(of: channelKeySize) { newKeySize in
							if channelKeySize == -1 {
								channelKey = "AQ=="
							} else {
								let key = generateChannelKey(size: channelKeySize)
								channelKey = key.base64ToBase64url()
							}
							hasChanges = true
						}
						.onChange(of: channelKey) { newKey in
							hasChanges = true
						}
					}
					Button {
						isPresentingSaveConfirm = true
					} label: {
						Label("save", systemImage: "square.and.arrow.down")
					}
					.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.bottom)
					.confirmationDialog(
						"are.you.sure",
						isPresented: $isPresentingSaveConfirm,
						titleVisibility: .visible
					) {
						Button("Save Channel \(channelIndex) to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
								
							var channel = Channel()
							channel.index = channelIndex
							channel.settings.name = channelName
							channel.role = ChannelRoles(rawValue: channelRole)?.protoEnumValue() ?? .secondary
							channel.settings.uplinkEnabled = uplink
							channel.settings.downlinkEnabled = downlink

							
//							let adminMessageId =  bleManager.saveSerialModuleConfig(config: sc, fromUser: node!.user!, toUser: node!.user!)
//
//							if adminMessageId > 0 {
//								// Should show a saved successfully alert once I know that to be true
//								// for now just disable the button after a successful save
//								hasChanges = false
//								goBack()
//							}
						}
					}
					.presentationDetents([.medium, .large])
				}
			}
		}
		.navigationTitle("channels")
		.navigationSplitViewStyle(.balanced)
		.navigationBarItems(trailing:
		ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			bleManager.context = context
		}
	}
}
