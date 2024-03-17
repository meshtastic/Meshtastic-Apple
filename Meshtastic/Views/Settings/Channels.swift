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
	@State private var supportedVersion = true
	
	/// Minimum Version for granular position configuration
	@State var minimumVersion = "2.2.24"

	var body: some View {

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
							} else if channelKey.count == 4 {
								channelKeySize = 1
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
							
							print("Position Precision \(channel.positionPrecision)")
							//self.positionPrecision = State(initialValue: Double(self.channel.positionPrecision))
							positionPrecision = Double(channel.positionPrecision)
							if !supportedVersion && channelRole == 1 {
								positionPrecision = 32
								preciseLocation = true
								positionsEnabled = true
								
							} else if !supportedVersion && channelRole == 2 {
								positionPrecision = 0
								preciseLocation = false
								positionsEnabled = false
							} else {
								if positionPrecision == 32 {
									preciseLocation = true
									positionsEnabled = true
								} else {
									preciseLocation = false
								}
								if positionPrecision == 0 {
									positionsEnabled = false
								} else {
									positionsEnabled = true
								}
							}
							hasChanges = false
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
				ChannelForm(channelIndex: $channelIndex, channelName: $channelName, channelKeySize: $channelKeySize, channelKey: $channelKey, channelRole: $channelRole, uplink: $uplink, downlink: $downlink, positionPrecision: $positionPrecision, preciseLocation: $preciseLocation, positionsEnabled: $positionsEnabled, hasChanges: $hasChanges, hasValidKey: $hasValidKey, supportedVersion: $supportedVersion)
				.onAppear {
					supportedVersion = bleManager.connectedVersion == "0.0.0" ||  self.minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedAscending || minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedSame
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
								let objects = channelEntity.allPrivateMessages
								for object in objects {
									context.delete(object)
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
							//_ = bleManager.getChannel(channel: channel, fromUser: node!.user!, toUser: node!.user!)
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
					preciseLocation = false
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
