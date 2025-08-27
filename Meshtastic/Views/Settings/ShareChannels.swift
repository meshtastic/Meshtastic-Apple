//
//  ShareChannel.swift
//  MeshtasticApple
//
//  Copyright(c) Garth Vander Houwen 4/8/22.
//
import SwiftUI
import CoreData
import CoreImage.CIFilterBuiltins
import MeshtasticProtobufs
import TipKit

struct QrCodeImage {
	let context = CIContext()

	func generateQRCode(from text: String) -> UIImage {
		var qrImage = UIImage(systemName: "xmark.circle") ?? UIImage()
		let data = Data(text.utf8)
		let filter = CIFilter.qrCodeGenerator()
		filter.setValue(data, forKey: "inputMessage")

		let transform = CGAffineTransform(scaleX: 20, y: 20)
		if let outputImage = filter.outputImage?.transformed(by: transform) {
			if let image = context.createCGImage(
				outputImage,
				from: outputImage.extent) {
				qrImage = UIImage(cgImage: image)
			}
		}
		return qrImage
	}
}

struct ShareChannels: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var dismiss
	@State var channelSet: ChannelSet = ChannelSet()
	@State var includeChannel0 = true
	@State var includeChannel1 = true
	@State var includeChannel2 = true
	@State var includeChannel3 = true
	@State var includeChannel4 = true
	@State var includeChannel5 = true
	@State var includeChannel6 = true
	@State var includeChannel7 = true
	@State var replaceChannels = true
	var node: NodeInfoEntity?
	@State private var channelsUrl =  "https://www.meshtastic.org/e/#"
	var qrCodeImage = QrCodeImage()
	@State private var showingHelp = false

	var body: some View {

		VStack {
			TipView(ShareChannelsTip(), arrowEdge: .bottom)
		}
		GeometryReader { bounds in
			let smallest = min(bounds.size.width, bounds.size.height)
			ScrollView {
				if node != nil && node?.myInfo != nil {
					Grid {
						GridRow {
							Spacer()
							Text("Include")
								.font(.caption)
								.fontWeight(.bold)
								.padding(.trailing)
							Text("Channel")
								.font(.caption)
								.fontWeight(.bold)
								.padding(.trailing)
							Text("Encrypted")
								.font(.caption)
								.fontWeight(.bold)
						}
						ForEach(node?.myInfo?.channels?.array as? [ChannelEntity] ?? [], id: \.self) { (channel: ChannelEntity) in
							GridRow {
								Spacer()
								if channel.index == 0 {
									Toggle("Channel 0 Included", isOn: $includeChannel0)
										.toggleStyle(.switch)
										.labelsHidden()
									Text(((channel.name!.isEmpty ? "Primary" : channel.name) ?? "Primary").camelCaseToWords())
									ChannelLock(channel: channel)
								} else if channel.index == 1 && channel.role > 0 {
									Toggle("Channel 1 Included", isOn: $includeChannel1)
										.toggleStyle(.switch)
										.labelsHidden()
										.disabled(channel.role == 1)
									Text(((channel.name!.isEmpty ? "Channel\(channel.index)" : channel.name) ?? "Channel\(channel.index)").camelCaseToWords()).fixedSize()
									if channel.psk?.hexDescription.count ??  0 <  3 {
										Image(systemName: "lock.slash.fill")
											.foregroundColor(.red)
									} else {
										Image(systemName: "lock.fill")
											.foregroundColor(.green)
									}
								} else if channel.index == 2 && channel.role > 0 {
									Toggle("Channel 2 Included", isOn: $includeChannel2)
										.toggleStyle(.switch)
										.labelsHidden()
										.disabled(channel.role == 1)
									Text(((channel.name!.isEmpty ? "Channel\(channel.index)" : channel.name) ?? "Channel\(channel.index)").camelCaseToWords()).fixedSize()
									if channel.psk?.hexDescription.count ??  0 <  3 {
										Image(systemName: "lock.slash.fill")
											.foregroundColor(.red)
									} else {
										Image(systemName: "lock.fill")
											.foregroundColor(.green)
									}
								} else if channel.index == 3 && channel.role > 0 {
									Toggle("Channel 3 Included", isOn: $includeChannel3)
										.toggleStyle(.switch)
										.labelsHidden()
										.disabled(channel.role == 1)
									Text(((channel.name!.isEmpty ? "Channel\(channel.index)" : channel.name) ?? "Channel\(channel.index)").camelCaseToWords()).fixedSize()
									if channel.psk?.hexDescription.count ??  0 <  3 {
										Image(systemName: "lock.slash.fill")
											.foregroundColor(.red)
									} else {
										Image(systemName: "lock.fill")
											.foregroundColor(.green)
									}
								} else if channel.index == 4  && channel.role > 0 {
									Toggle("Channel 4 Included", isOn: $includeChannel4)
										.toggleStyle(.switch)
										.labelsHidden()
										.disabled(channel.role == 1)
									Text(((channel.name!.isEmpty ? "Channel\(channel.index)" : channel.name) ?? "Channel\(channel.index)").camelCaseToWords()).fixedSize()
									if channel.psk?.hexDescription.count ??  0 <  3 {
										Image(systemName: "lock.slash.fill")
											.foregroundColor(.red)
									} else {
										Image(systemName: "lock.fill")
											.foregroundColor(.green)
									}
								} else if channel.index == 5 && channel.role > 0 {
									Toggle("Channel 5 Included", isOn: $includeChannel5)
										.toggleStyle(.switch)
										.labelsHidden()
										.disabled(channel.role == 1)
									Text(((channel.name!.isEmpty ? "Channel\(channel.index)" : channel.name) ?? "Channel\(channel.index)").camelCaseToWords()).fixedSize()
									if channel.psk?.hexDescription.count ??  0 <  3 {
										Image(systemName: "lock.slash.fill")
											.foregroundColor(.red)
									} else {
										Image(systemName: "lock.fill")
											.foregroundColor(.green)
									}
								} else if channel.index == 6  && channel.role > 0 {
									Toggle("Channel 6 Included", isOn: $includeChannel6)
										.toggleStyle(.switch)
										.labelsHidden()
										.disabled(channel.role == 1)
									Text(((channel.name!.isEmpty ? "Channel\(channel.index)" : channel.name) ?? "Channel\(channel.index)").camelCaseToWords()).fixedSize()
									if channel.psk?.hexDescription.count ??  0 <  3 {
										Image(systemName: "lock.slash.fill")
											.foregroundColor(.red)
									} else {
										Image(systemName: "lock.fill")
											.foregroundColor(.green)
									}
								} else if channel.index == 7 && channel.role > 0 {
									Toggle("Channel 7 Included", isOn: $includeChannel7)
										.toggleStyle(.switch)
										.labelsHidden()
										.disabled(channel.role == 1)
									Text(((channel.name!.isEmpty ? "Channel\(channel.index)" : channel.name) ?? "Channel\(channel.index)").camelCaseToWords()).fixedSize()
									if channel.psk?.hexDescription.count ??  0 <  3 {
										Image(systemName: "lock.slash.fill")
											.foregroundColor(.red)
									} else {
										Image(systemName: "lock.fill")
											.foregroundColor(.green)
									}
								}
								Spacer()
							}
						}
					}

					let qrImage = qrCodeImage.generateQRCode(from: channelsUrl)
					VStack {
						if node != nil {
							Toggle(isOn: $replaceChannels) {
								Label(replaceChannels ? "Replace Channels" : "Add Channels", systemImage: replaceChannels ? "arrow.triangle.2.circlepath.circle" : "plus.app")
							}
							.tint(.accentColor)
							.toggleStyle(.button)
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.large)
							.padding(.top)
							.padding(.bottom)

							ShareLink("Share QR Code & Link",
										item: Image(uiImage: qrImage),
										subject: Text("Meshtastic Node \(node?.user?.shortName ?? "????") has shared channels with you"),
										message: Text(channelsUrl),
										preview: SharePreview("Meshtastic Node \(node?.user?.shortName ?? "????") has shared channels with you",
															image: Image(uiImage: qrImage))
							)
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.large)
							.padding(.bottom)

							Image(uiImage: qrImage)
								.resizable()
								.scaledToFit()
								.frame(
									minWidth: smallest * (UIDevice.current.userInterfaceIdiom == .phone ? 0.75 : 0.6),
									maxWidth: smallest * (UIDevice.current.userInterfaceIdiom == .phone ? 0.75 : 0.6),
									minHeight: smallest * (UIDevice.current.userInterfaceIdiom == .phone ? 0.75 : 0.6),
									maxHeight: smallest * (UIDevice.current.userInterfaceIdiom == .phone ? 0.75 : 0.6),
									alignment: .top
								)
						}
					}
				}
			}
			.sheet(isPresented: $showingHelp) {
				ChannelsHelp()
					.presentationDetents([.large])
					.presentationDragIndicator(.visible)
			}
			.safeAreaInset(edge: .bottom, alignment: .leading) {
				HStack {
					Button(action: {
						withAnimation {
							showingHelp = !showingHelp
						}
					}) {
						Image(systemName: !showingHelp ? "questionmark.circle" : "questionmark.circle.fill")
							.padding(.vertical, 5)
					}
					.tint(Color(UIColor.secondarySystemBackground))
					.foregroundColor(.accentColor)
					.buttonStyle(.borderedProminent)
				}
				.controlSize(.regular)
				.padding(5)
			}
			.padding(.bottom, 5)
			.navigationTitle("Generate QR Code")
			.navigationBarTitleDisplayMode(.inline)
			.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			})
			.onAppear {
				generateChannelSet()
			}
			.onChange(of: includeChannel0) { generateChannelSet() }
			.onChange(of: includeChannel1) { generateChannelSet() }
			.onChange(of: includeChannel2) { generateChannelSet() }
			.onChange(of: includeChannel3) { generateChannelSet() }
			.onChange(of: includeChannel4) { generateChannelSet() }
			.onChange(of: includeChannel5) { generateChannelSet() }
			.onChange(of: includeChannel6) { generateChannelSet() }
			.onChange(of: includeChannel7) { generateChannelSet() }
			.onChange(of: replaceChannels) { generateChannelSet() }
		}
	}
	func generateChannelSet() {
		channelSet = ChannelSet()
		var loRaConfig = Config.LoRaConfig()
		loRaConfig.region =  RegionCodes(rawValue: Int(node?.loRaConfig?.regionCode ?? 0))!.protoEnumValue()
		loRaConfig.modemPreset = ModemPresets(rawValue: Int(node?.loRaConfig?.modemPreset ?? 0))!.protoEnumValue()
		loRaConfig.bandwidth = UInt32(node?.loRaConfig?.bandwidth ?? 0)
		loRaConfig.spreadFactor = UInt32(node?.loRaConfig?.spreadFactor ?? 0)
		loRaConfig.codingRate = UInt32(node?.loRaConfig?.codingRate ?? 0)
		loRaConfig.frequencyOffset = node?.loRaConfig?.frequencyOffset ?? 0
		loRaConfig.hopLimit = UInt32(node?.loRaConfig?.hopLimit ?? 3)
		loRaConfig.txEnabled = node?.loRaConfig?.txEnabled ?? false
		loRaConfig.txPower = node?.loRaConfig?.txPower ?? 0
		loRaConfig.usePreset = node?.loRaConfig?.usePreset ?? true
		loRaConfig.channelNum = UInt32(node?.loRaConfig?.channelNum ?? 0)
		loRaConfig.sx126XRxBoostedGain = node?.loRaConfig?.sx126xRxBoostedGain ?? false
		loRaConfig.ignoreMqtt = node?.loRaConfig?.ignoreMqtt ?? false
		channelSet.loraConfig = loRaConfig
		if node?.myInfo?.channels != nil && node?.myInfo?.channels?.count ?? 0 > 0 {
			for ch in node?.myInfo?.channels?.array as? [ChannelEntity] ?? [] where ch.role > 0 {
				var includeChannel = false
				switch ch.index {
				case 0:
					if includeChannel0 {
						includeChannel = true
					}
				case 1:
					if includeChannel1 {
						includeChannel = true
					}
				case 2:
					if includeChannel2 {
						includeChannel = true
					}
				case 3:
					if includeChannel3 {
						includeChannel = true
					}
				case 4:
					if includeChannel4 {
						includeChannel = true
					}
				case 5:
					if includeChannel5 {
						includeChannel = true
					}
				case 6:
					if includeChannel6 {
						includeChannel = true
					}
				case 7:
					if includeChannel7 {
						includeChannel = true
					}
				default:
					includeChannel = false
				}
				if includeChannel {
					var channelSettings = ChannelSettings()
					channelSettings.name = ch.name!
					channelSettings.psk = ch.psk!
					channelSettings.id = UInt32(ch.id)
					channelSet.settings.append(channelSettings)
				}
			}
			guard let settingsString = try? channelSet.serializedData().base64EncodedString() else {
				return
			}
			channelsUrl = ("https://meshtastic.org/e/\(replaceChannels ? "" : "?add=true")#\(settingsString.base64ToBase64url())")
		}
	}
}
