//
//  ShareChannel.swift
//  MeshtasticApple
//
//  Copyright(c) Garth Vander Houwen 4/8/22.
//
import SwiftUI
import SwiftData
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

	@Environment(\.modelContext) private var context
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
	@State private var channelsUrl =  "https://meshtastic.org/e/#"
	var qrCodeImage = QrCodeImage()
	@State private var showingHelp = false

	private var shareableChannels: [ChannelEntity] {
		(node?.myInfo?.channels ?? [])
			.filter { $0.role > 0 }
			.sorted { $0.index < $1.index }
	}

	var body: some View {

		VStack {
			TipView(ShareChannelsTip(), arrowEdge: .bottom)
				.tipBackground(Color(.secondarySystemBackground))
				.listRowSeparator(.hidden)
		}
		.padding(.horizontal)

		GeometryReader { bounds in
			let smallest = min(bounds.size.width, bounds.size.height)
			ScrollView {
				if node != nil && node?.myInfo != nil {
					if shareableChannels.isEmpty {
						ContentUnavailableView(
							"No Shareable Channels",
							systemImage: "qrcode",
							description: Text("Connect to a radio with channel settings before sharing.")
						)
						.padding(.vertical, 24)
					} else {
						channelSelectionGrid

						if channelSet.settings.isEmpty {
							ContentUnavailableView(
								"No Channels Selected",
								systemImage: "qrcode",
								description: Text("Select at least one channel before sharing.")
							)
							.padding(.vertical, 24)
						} else if channelsUrl.isEmpty {
							ContentUnavailableView(
								"Share Link Unavailable",
								systemImage: "qrcode",
								description: Text("Select channels again before sharing.")
							)
							.padding(.vertical, 24)
						} else {
							let qrImage = qrCodeImage.generateQRCode(from: channelsUrl)
							VStack {
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
			}
			.sheet(isPresented: $showingHelp) {
				ChannelsHelp()
					.presentationDetents([.large])
					#if !targetEnvironment(macCatalyst)
					.presentationDragIndicator(.visible)
					#endif
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
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
				}
			}
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

	private var channelSelectionGrid: some View {
		Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
			GridRow {
				Text("Include")
					.font(.caption)
					.fontWeight(.bold)
				Text("Channel")
					.font(.caption)
					.fontWeight(.bold)
				Text("Encrypted")
					.font(.caption)
					.fontWeight(.bold)
			}

			ForEach(shareableChannels, id: \.self) { channel in
				GridRow {
					Toggle("Channel \(channel.index) Included", isOn: includeBinding(for: channel.index))
						.toggleStyle(.switch)
						.labelsHidden()
						.disabled(channel.role == 1 && channel.index != 0)
					Text(channelDisplayName(channel))
						.fixedSize(horizontal: false, vertical: true)
					ChannelLock(channel: channel)
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .center)
		.padding(.horizontal)
	}

	private func includeBinding(for index: Int32) -> Binding<Bool> {
		switch index {
		case 0:
			return $includeChannel0
		case 1:
			return $includeChannel1
		case 2:
			return $includeChannel2
		case 3:
			return $includeChannel3
		case 4:
			return $includeChannel4
		case 5:
			return $includeChannel5
		case 6:
			return $includeChannel6
		case 7:
			return $includeChannel7
		default:
			return .constant(false)
		}
	}

	private func channelDisplayName(_ channel: ChannelEntity) -> String {
		if channel.index == 0 && (channel.name?.isEmpty ?? true) {
			return "Primary"
		}
		return ((channel.name?.isEmpty ?? true ? "Channel\(channel.index)" : channel.name) ?? "Channel\(channel.index)").camelCaseToWords()
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
		loRaConfig.overrideFrequency = node?.loRaConfig?.overrideFrequency ?? 0.0
		channelSet.loraConfig = loRaConfig

		guard node?.myInfo != nil && (node?.myInfo?.channels.count ?? 0) > 0 else {
			channelsUrl = ""
			return
		}

		for ch in node?.myInfo?.channels ?? [] where ch.role > 0 {
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
				channelSettings.name = ch.name ?? ""
				channelSettings.psk = ch.psk ?? Data()
				channelSettings.id = UInt32(ch.id)
				channelSettings.moduleSettings.positionPrecision = UInt32(ch.positionPrecision)
				channelSettings.moduleSettings.isMuted = ch.mute
				channelSet.settings.append(channelSettings)
			}
		}

		guard !channelSet.settings.isEmpty else {
			channelsUrl = ""
			return
		}
		guard let urlString = try? MeshtasticChannelURL.urlString(for: channelSet, addChannels: !replaceChannels) else {
			channelsUrl = ""
			return
		}
		channelsUrl = urlString
	}
}
