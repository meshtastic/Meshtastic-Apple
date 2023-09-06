//
//  ShareChannel.swift
//  MeshtasticApple
//
//  Copyright(c) Garth Vander Houwen 4/8/22.
//
import SwiftUI
import CoreData
import CoreImage.CIFilterBuiltins
#if canImport(TipKit)
import TipKit
#endif

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
	@EnvironmentObject var bleManager: BLEManager
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
	var node: NodeInfoEntity?
	@State private var channelsUrl =  "https://www.meshtastic.org/e/#"
	var qrCodeImage = QrCodeImage()

	var body: some View {
		GeometryReader { bounds in
			let smallest = min(bounds.size.width, bounds.size.height)
			ScrollView {
				if node != nil && node?.myInfo != nil {
					
					if #available(iOS 17.0, macOS 14.0, *) {
						VStack {
							TipView(ShareChannelsTip(), arrowEdge: .top)
						}
					}
					Grid {
						GridRow {
							Spacer()
							Text("include")
								.font(.caption)
								.fontWeight(.bold)
								.padding(.trailing)
							Text("channel")
								.font(.caption)
								.fontWeight(.bold)
								.padding(.trailing)
							Text("encrypted")
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
									if channel.psk?.hexDescription.count ??  0 <  3 {
										Image(systemName: "lock.slash")
											.foregroundColor(.red)
									} else {
										Image(systemName: "lock.fill")
											.foregroundColor(.green)
									}
								} else if channel.index == 1 && channel.role > 0 {
									Toggle("Channel 1 Included", isOn: $includeChannel1)
										.toggleStyle(.switch)
										.labelsHidden()
										.disabled(channel.role == 1)
									Text(((channel.name!.isEmpty ? "Channel\(channel.index)" : channel.name) ?? "Channel\(channel.index)").camelCaseToWords()).fixedSize()
									if channel.psk?.hexDescription.count ??  0 <  3 {
										Image(systemName: "lock.slash")
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
										Image(systemName: "lock.slash")
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
										Image(systemName: "lock.slash")
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
										Image(systemName: "lock.slash")
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
										Image(systemName: "lock.slash")
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
										Image(systemName: "lock.slash")
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
										Image(systemName: "lock.slash")
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
									minWidth: smallest * 0.95,
									maxWidth: smallest * 0.95,
									minHeight: smallest * 0.95,
									maxHeight: smallest * 0.95,
									alignment: .top
								)
						}
					}
				}
			}
			.navigationTitle("generate.qr.code")
			.navigationBarTitleDisplayMode(.inline)
			.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
			})
			.onAppear {
				bleManager.context = context
				generateChannelSet()
			}
			.onChange(of: includeChannel0) { _ in generateChannelSet()	}
			.onChange(of: includeChannel1) { _ in generateChannelSet()	}
			.onChange(of: includeChannel2) { _ in generateChannelSet()	}
			.onChange(of: includeChannel3) { _ in generateChannelSet()	}
			.onChange(of: includeChannel4) { _ in generateChannelSet()	}
			.onChange(of: includeChannel5) { _ in generateChannelSet()	}
			.onChange(of: includeChannel6) { _ in generateChannelSet() }
			.onChange(of: includeChannel7) { _ in generateChannelSet() }
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
		channelSet.loraConfig = loRaConfig
		if node?.myInfo?.channels != nil && node?.myInfo?.channels?.count ?? 0 > 0 {
			for ch in node?.myInfo?.channels?.array as? [ChannelEntity] ?? [] {
				if ch.role > 0 {

					if ch.index == 0 && includeChannel0 || ch.index == 1 && includeChannel1 || ch.index == 2 && includeChannel2 || ch.index == 3 && includeChannel3 ||
						ch.index == 4 && includeChannel4 || ch.index == 5 && includeChannel5 || ch.index == 6 && includeChannel6 || ch.index == 7 && includeChannel7 {

						var channelSettings = ChannelSettings()
							channelSettings.name = ch.name!
							channelSettings.psk = ch.psk!
							channelSettings.id = UInt32(ch.id)
							channelSettings.uplinkEnabled = ch.uplinkEnabled
							channelSettings.downlinkEnabled = ch.downlinkEnabled
							channelSet.settings.append(channelSettings)
					}
				}
			}
			let settingsString = try! channelSet.serializedData().base64EncodedString()
			channelsUrl = ("https://meshtastic.org/e/#" + settingsString.base64ToBase64url())
		}
	}
}
