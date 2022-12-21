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
	
	@State var hasChanges = false
	@State private var isPresentingEditView = false
	@State private var isPresentingSaveConfirm: Bool = false
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
							channelKey = channel.psk?.base64EncodedString() ?? ""
							if channelKey.count == 0 {
								channelKeySize = 0
							} else if channelKey == "AQ==" {
								channelKeySize = -1
							} else if channelKey.count == 24 {
								channelKeySize = 16
							} else if channelKey.count == 32 {
								channelKeySize = 24
							} else if channelKey.count == 44 {
								channelKeySize = 32
							}
							isPresentingEditView = true
							channelName = channel.name ?? "Channel\(channelIndex)"
							uplink = channel.uplinkEnabled
							downlink = channel.downlinkEnabled
							hasChanges = false
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
					hasChanges = false
					
				} label: {
					Label("Add Channel", systemImage: "plus.square")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.sheet(isPresented: $isPresentingEditView) {
					
					#if targetEnvironment(macCatalyst)
					Text("channel")
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
								.disableAutocorrection(true)
								.keyboardType(.alphabet)
								.foregroundColor(Color.gray)
								.onChange(of: channelName, perform: { value in
									channelName = channelName.replacing(" ", with: "")
									let totalBytes = channelName.utf8.count
									// Only mess with the value if it is too big
									if totalBytes > 11 {
										let firstNBytes = Data(channelName.utf8.prefix(11))
										if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
											// Set the channelName back to the last place where it was the right size
											channelName = maxBytesString
										}
									}
									hasChanges = true
								})
							}
							HStack {
								Picker("Key Size", selection: $channelKeySize) {
									Text("Empty").tag(0)
									Text("Default").tag(-1)
									Text("1 bit").tag(1)
									Text("128 bit").tag(16)
									Text("192 bit").tag(24)
									Text("256 bit").tag(32)
								}
								.pickerStyle(DefaultPickerStyle())
								Spacer()
								Button {
									if channelKeySize == -1 {
										channelKey = "AQ=="
									} else {
										let key = generateChannelKey(size: channelKeySize)
										channelKey = key
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
							.textSelection(.enabled)
							Picker("Channel Role", selection: $channelRole) {
								if channelRole == 1 {
									Text("Primary").tag(1)
								} else{
									Text("Disabled").tag(0)
									Text("Secondary").tag(2)
								}
							}
							.pickerStyle(DefaultPickerStyle())
							.disabled(channelRole == 1)
							Toggle("Uplink Enabled", isOn: $uplink)
								.toggleStyle(SwitchToggleStyle(tint: .accentColor))
							Toggle("Downlink Enabled", isOn: $downlink)
								.toggleStyle(SwitchToggleStyle(tint: .accentColor))
							
						}
						.onSubmit {
							//validate(name: channelName)
						}
						.onChange(of: channelName) { newName in
							hasChanges = true
						}
						.onChange(of: channelKeySize) { newKeySize in
							if channelKeySize == -1 {
								channelKey = "AQ=="
							} else {
								let key = generateChannelKey(size: channelKeySize)
								channelKey = key
							}
							hasChanges = true
						}
						.onChange(of: channelKey) { newKey in
							hasChanges = true
						}
						.onChange(of: channelRole) { newRole in
							hasChanges = true
						}
						.onChange(of: uplink) { newUplink in
							hasChanges = true
						}
						.onChange(of: downlink) { newDownlink in
							hasChanges = true
						}
					}
					HStack {
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
								channel.settings.psk = Data(base64Encoded: channelKey, options: .ignoreUnknownCharacters) ?? Data()
								channel.role = ChannelRoles(rawValue: channelRole)?.protoEnumValue() ?? .secondary
								channel.settings.uplinkEnabled = uplink
								channel.settings.downlinkEnabled = downlink
							}
						}
						#if targetEnvironment(macCatalyst)
						Button {
							isPresentingEditView = false
						} label: {
							Label("Close", systemImage: "xmark")
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.padding(.bottom)
						#endif
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
