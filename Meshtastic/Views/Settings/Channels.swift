//
//  Channels.swift
//  Meshtastic Apple
//
//  Copyright(c) Garth Vander Houwen 4/8/22.
//

import SwiftUI
import CoreData
import MapKit
#if canImport(TipKit)
import TipKit
#endif

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
	@Environment(\.dismiss) private var goBack
	@Environment(\.sizeCategory) var sizeCategory

	var node: NodeInfoEntity?

	@State var hasChanges = false
	@State var hasValidKey = true
	@State private var isPresentingEditView = false
	@State private var isPresentingSaveConfirm: Bool = false
	@State private var channelIndex: Int32 = 0
	@State private var channelName = ""
	@State private var channelKeySize = 16
	@State private var channelKey = "AQ=="
	@State private var channelRole = 0
	@State private var uplink = false
	@State private var downlink = false
	
	@State private var positionPrecision = 32.0
	@State private var preciseLocation = true
	@State private var positionsEnabled = true
	
	/// Minimum Version for granular position configuration
	@State var minimumVersion = "2.2.20"
	

	var body: some View {
		
		let supportedVersion = bleManager.connectedVersion == "0.0.0" ||  self.minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedAscending || minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedSame

		VStack {
			List {
				if #available(iOS 17.0, macOS 14.0, *) {
					TipView(CreateChannelsTip(), arrowEdge: .bottom)
				}
				if node != nil && node?.myInfo != nil {
					ForEach(node?.myInfo?.channels?.array as? [ChannelEntity] ?? [], id: \.self) { (channel: ChannelEntity) in
						Button(action: {
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
							channelName = channel.name ?? ""
							uplink = channel.uplinkEnabled
							downlink = channel.downlinkEnabled
							hasChanges = false
							if !supportedVersion && channelRole == 1 {
								positionPrecision = 32
								preciseLocation = true
								positionsEnabled = true
								
							} else if !supportedVersion && channelRole == 2 {
								positionPrecision = 0
								preciseLocation = false
								positionsEnabled = false
							}
							isPresentingEditView = true
						}) {
							VStack(alignment: .leading) {
								HStack {
									CircleText(text: String(channel.index), color: .accentColor, circleSize: 45)
										.padding(.trailing, 5)
										.brightness(0.1)
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
			.sheet(isPresented: $isPresentingEditView) {
				
				#if targetEnvironment(macCatalyst)
				Text("channel")
					.font(.largeTitle)
					.padding()
				#endif
				Form {
					Section(header: Text("channel details")) {
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
							.onChange(of: channelName, perform: { _ in
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
								Text("1 byte").tag(1)
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
						HStack(alignment: .center) {
							Text("Key")
							Spacer()
							TextField(
								"Key",
								text: $channelKey,
								axis: .vertical
							)
							.padding(6)
							.disableAutocorrection(true)
							.keyboardType(.alphabet)
							.foregroundColor(Color.gray)
							.textSelection(.enabled)
							.background(
								RoundedRectangle(cornerRadius: 10.0)
									.stroke(
										hasValidKey ?
										Color.clear :
											Color.red
										, lineWidth: 2.0)
								
							)
							.onChange(of: channelKey, perform: { _ in
								let tempKey = Data(base64Encoded: channelKey) ?? Data()
								if tempKey.count == channelKeySize || channelKeySize == -1{
									hasValidKey = true
								}
								else {
									hasValidKey = false
								}
								hasChanges = true
							})
							.disabled(channelKeySize <= 0)
						}
						HStack {
							if channelRole == 1 {
								Picker("Channel Role", selection: $channelRole) {
									Text("Primary").tag(1)
								}
								.pickerStyle(.automatic)
								.disabled(true)
							} else {
								Text("Channel Role")
								Spacer()
								Picker("Channel Role", selection: $channelRole) {
									Text("Disabled").tag(0)
									Text("Secondary").tag(2)
								}
								.pickerStyle(.segmented)
							}
						}
					}
					
					Section(header: Text("position")) {
						
						VStack(alignment: .leading) {
							Toggle(isOn: $positionsEnabled) {
								Label(channelRole == 1 ? "Positions Enabled" : "Allow Position Requests", systemImage: positionsEnabled ? "mappin" : "mappin.slash")
							}
							.toggleStyle(SwitchToggleStyle(tint: .accentColor))
							.disabled(!supportedVersion)
						}
						
						if positionsEnabled {
							VStack(alignment: .leading) {
								Toggle(isOn: $preciseLocation) {
									Label("Precise Location", systemImage: "scope")
								}
								.toggleStyle(SwitchToggleStyle(tint: .accentColor))
								.disabled(!supportedVersion)
								.listRowSeparator(.visible)
								.onChange(of: preciseLocation) { pl in
									if pl == false {
										positionPrecision = 13
									}
								}
							}
							
							if !preciseLocation {
								VStack(alignment: .leading) {
									Label("Reduce Precision", systemImage: "location.viewfinder")
									Slider(
										value: $positionPrecision,
										in: 11...16,
										step: 1
									)
									{
									} minimumValueLabel: {
										Image(systemName: "minus")
									} maximumValueLabel: {
										Image(systemName: "plus")
									}
									Text(PositionPrecision(rawValue: Int(positionPrecision))?.description ?? "")
										.foregroundColor(.gray)
										.font(.callout)
								}
							}
						}
					}
					Section(header: Text("mqtt")) {
						Toggle(isOn: $uplink) {
							Label("Uplink Enabled", systemImage: "arrowshape.up")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.listRowSeparator(.visible)

						Toggle(isOn: $downlink) {
							Label("Downlink Enabled", systemImage: "arrowshape.down")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.listRowSeparator(.visible)
					}
				}
				.onAppear {
					let tempKey = Data(base64Encoded: channelKey) ?? Data()
					if tempKey.count == channelKeySize || channelKeySize == -1{
						hasValidKey = true
					}
					else {
						hasValidKey = false
					}
				}
				.onChange(of: channelName) { _ in
					hasChanges = true
				}
				.onChange(of: channelKeySize) { _ in
					if channelKeySize == -1 {
						channelKey = "AQ=="
					} else {
						let key = generateChannelKey(size: channelKeySize)
						channelKey = key
					}
					hasChanges = true
				}
				.onChange(of: channelKey) { _ in
					hasChanges = true
				}
				.onChange(of: channelRole) { _ in
					hasChanges = true
				}
				.onChange(of: uplink) { _ in
					hasChanges = true
				}
				.onChange(of: downlink) { _ in
					hasChanges = true
				}
				HStack {
					Button {
						var channel = Channel()
						channel.index = channelIndex
						channel.role = ChannelRoles(rawValue: channelRole)?.protoEnumValue() ?? .secondary
						if channel.role != Channel.Role.disabled {
							channel.index = channelIndex
							channel.settings.name = channelName
							channel.settings.psk = Data(base64Encoded: channelKey) ?? Data()
							channel.settings.uplinkEnabled = uplink
							channel.settings.downlinkEnabled = downlink
							channel.settings.moduleSettings.positionPrecision = UInt32(positionPrecision)
							
							let newChannel = ChannelEntity(context: context)
							newChannel.id = Int32(channel.index)
							newChannel.index = Int32(channel.index)
							newChannel.uplinkEnabled = channel.settings.uplinkEnabled
							newChannel.downlinkEnabled = channel.settings.downlinkEnabled
							newChannel.name = channel.settings.name
							newChannel.role = Int32(channel.role.rawValue)
							newChannel.psk = channel.settings.psk
							newChannel.positionPrecision = Int32(positionPrecision)

							guard let mutableChannels = node?.myInfo?.channels?.mutableCopy() as? NSMutableOrderedSet else {
								return
							}
							if mutableChannels.contains(newChannel) {
								mutableChannels.replaceObject(at: Int(newChannel.index), with: newChannel)
							} else {
								mutableChannels.add(newChannel)
							}
							node!.myInfo!.channels = mutableChannels.copy() as? NSOrderedSet
							context.refresh(newChannel, mergeChanges: true)
							do {
								try context.save()
								print("💾 Saved Channel: \(channel.settings.name)")
							} catch {
								context.rollback()
								let nsError = error as NSError
								print("💥 Unresolved Core Data error in the channel editor. Error: \(nsError)")
							}
						} else {
							if channelIndex <= node!.myInfo!.channels?.count ?? 0 {
								guard let channelEntity = node!.myInfo!.channels?[Int(channelIndex)] as? ChannelEntity else {
									return
								}
								context.delete(channelEntity)
								do {
									try context.save()
									print("💾 Deleted Channel: \(channel.settings.name)")
								} catch {
									context.rollback()
									let nsError = error as NSError
									print("💥 Unresolved Core Data error in the channel editor. Error: \(nsError)")
								}
							}
						}

						let adminMessageId =  bleManager.saveChannel(channel: channel, fromUser: node!.user!, toUser: node!.user!)

						if adminMessageId > 0 {
							self.isPresentingEditView = false
							channelName = ""
							channelRole	= 2
							hasChanges = false
							_ = bleManager.getChannel(channel: channel, fromUser: node!.user!, toUser: node!.user!)
						}
					} label: {
						Label("save", systemImage: "square.and.arrow.down")
					}
					.disabled(bleManager.connectedPeripheral == nil || !hasChanges || !hasValidKey)
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.bottom)
					#if targetEnvironment(macCatalyst)
					Button {
						isPresentingEditView = false
					} label: {
						Label("close", systemImage: "xmark")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.bottom)
					#endif
				}
				.presentationDetents([.fraction(0.85), .large])
				.presentationDragIndicator(.visible)
			}
			if node?.myInfo?.channels?.array.count ?? 0 < 8 && node != nil {

				Button {
					let channelIndexes = node?.myInfo?.channels?.compactMap({(ch) -> Int in
						return (ch as AnyObject).index
					})
					let firstChannelIndex = firstMissingChannelIndex(channelIndexes ?? [])
					channelKeySize = 16
					let key = generateChannelKey(size: channelKeySize)
					channelName = ""
					channelIndex = Int32(firstChannelIndex)
					channelRole = 2
					channelKey = key
					positionsEnabled = false
					positionPrecision = 0
					uplink = false
					downlink = false
					hasChanges = true
					isPresentingEditView = true

				} label: {
					Label("Add Channel", systemImage: "plus.square")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
			}
		}
		.navigationTitle("channels")
		.navigationBarItems(trailing:
		ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
		}
	}
}

func firstMissingChannelIndex(_ indexes: [Int]) -> Int {
	for element in 1...indexes.count {
		if !indexes.contains(element) {
			return element
		}
	}
	return indexes.count + 1
}


enum PositionPrecision: Int, CaseIterable, Identifiable {

	case eleven = 11
	case twelve = 12
	case thirteen = 13
	case fourteen = 14
	case fifteen = 15
	case sixteen = 16

	var id: Int { self.rawValue }
	
	var precisionMeters: Double {
		switch self {

		case .eleven:
			return 11672.736900000944
		case .twelve:
			return 5836.362884000802
		case .thirteen:
			return 2918.1758760007315
		case .fourteen:
			return 1459.0823719999053
		case .fifteen:
			return 729.5356200010741
		case .sixteen:
			return 364.7622440000765
		}
	}
	
	var description: String {
		let distanceFormatter = MKDistanceFormatter()
		switch self {

		case .eleven:
			return String.localizedStringWithFormat("position.precision %@".localized, String(distanceFormatter.string(fromDistance: precisionMeters)))
		case .twelve:
			return String.localizedStringWithFormat("position.precision %@".localized, String(distanceFormatter.string(fromDistance: precisionMeters)))
		case .thirteen:
			return String.localizedStringWithFormat("position.precision %@".localized, String(distanceFormatter.string(fromDistance: precisionMeters)))
		case .fourteen:
			return String.localizedStringWithFormat("position.precision %@".localized, String(distanceFormatter.string(fromDistance: precisionMeters)))
		case .fifteen:
			return String.localizedStringWithFormat("position.precision %@".localized, String(distanceFormatter.string(fromDistance: precisionMeters)))
		case .sixteen:
			return String.localizedStringWithFormat("position.precision %@".localized, String(distanceFormatter.string(fromDistance: precisionMeters)))
		}
	}
}
