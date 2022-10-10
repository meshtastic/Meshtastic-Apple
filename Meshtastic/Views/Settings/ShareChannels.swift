//
//  ShareChannel.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 4/8/22.
//
import SwiftUI
import CoreData
import CoreImage.CIFilterBuiltins


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
	@EnvironmentObject var userSettings: UserSettings
	@State var initialLoad: Bool = true
	
	@State var channelSet: ChannelSet = ChannelSet()
	@State var includeChannel0 = true
	@State var includeChannel1 = false
	@State var includeChannel2 = false
	@State var includeChannel3 = false
	@State var includeChannel4 = false
	@State var includeChannel5 = false
	@State var includeChannel6 = false
	@State var includeChannel7 = false
	
	@State var isPresentingHelp = false
	
	var node: NodeInfoEntity?
	
	@State private var channelsUrl =  "https://meshtastic.org/e/#"
	var qrCodeImage = QrCodeImage()
	
	var body: some View {
		
		VStack {
			
			GeometryReader { bounds in
				
				let smallest = min(bounds.size.width, bounds.size.height)
				
				ScrollView {
					
					VStack {
						if node != nil {
							
							Grid(alignment: .top, horizontalSpacing: 2) {
								
								GridRow {
									Spacer()
									Text("Include")
										.font(.caption)
										.fontWeight(.bold)
										.padding(.trailing)
									Text("Channel Name")
										.font(.caption)
										.fontWeight(.bold)
										.padding(.trailing)
									Text("Encrypted")
										.font(.caption)
										.fontWeight(.bold)
									Spacer()
								}
								
								ForEach(node!.myInfo!.channels?.array as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in

									GridRow {
										Spacer()
										if channel.index == 0 {
											
											Toggle("Channel 0 Included", isOn: $includeChannel0)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(channel.role == 1)
											Text((channel.name!.isEmpty ? "Primary" : channel.name) ?? "Primary")
											
										} else if channel.index == 1 {
											Toggle("Channel 1 Included", isOn: $includeChannel1)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(channel.role == 0)
											Text((channel.name!.isEmpty ? "Channel \(channel.index)" : channel.name) ?? "Channel \(channel.index)")
										} else if channel.index == 2 {
											Toggle("Channel 2 Included", isOn: $includeChannel2)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(channel.role == 0)
											Text((channel.name!.isEmpty ? "Channel \(channel.index)" : channel.name) ?? "Channel \(channel.index)")
										} else if channel.index == 3 {
											Toggle("Channel 3 Included", isOn: $includeChannel3)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(channel.role == 0)
											Text((channel.name!.isEmpty ? "Channel \(channel.index)" : channel.name) ?? "Channel \(channel.index)")
										} else if channel.index == 4 {
											Toggle("Channel 4 Included", isOn: $includeChannel4)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(channel.role == 0)
											Text((channel.name!.isEmpty ? "Channel \(channel.index)" : channel.name) ?? "Channel \(channel.index)")
										} else if channel.index == 5 {
											Toggle("Channel 5 Included", isOn: $includeChannel5)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(channel.role == 0)
											Text((channel.name!.isEmpty ? "Channel \(channel.index)" : channel.name) ?? "Channel \(channel.index)")
										} else if channel.index == 6 {
											Toggle("Channel 6 Included", isOn: $includeChannel6)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(channel.role == 0)
											Text((channel.name!.isEmpty ? "Channel \(channel.index)" : channel.name) ?? "Channel \(channel.index)")
										} else if channel.index == 7 {
											Toggle("Channel 7 Included", isOn: $includeChannel7)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(channel.role == 0)
											Text((channel.name!.isEmpty ? "Admin" : channel.name) ?? "Admin")
										}
										if channel.role > 0 {
											Image(systemName: "lock.fill")
												.foregroundColor(.green)
										} else  {
											Image(systemName: "lock.slash")
											.foregroundColor(.gray)
										}
										Spacer()
									}
								}
							}
						}
					}
					let qrImage = qrCodeImage.generateQRCode(from: channelsUrl)
					
					VStack {
									
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
						
						Image(uiImage: qrImage)
							.resizable()
							.scaledToFit()
							.frame(
								minWidth: smallest * 0.65,
								maxWidth: smallest * 0.65,
								minHeight: smallest * 0.65,
								maxHeight: smallest * 0.65,
								alignment: .top
							)
						
						Button {
										
							isPresentingHelp = true
							
						} label: {
							
							Label("Help Me!", systemImage: "lifepreserver")
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.small)
						.padding(.top)
					}
				}
				.sheet(isPresented: $isPresentingHelp) {
					
					VStack {
						Text("Meshtastic Channels").font(.title)
						Text("A Meshtastic LoRa Mesh network can have up to 8 distinct channels.")
							.font(.headline)
							.padding(.bottom)
						Text("Primary Channel").font(.title2)
						Text("The first channel is the Primary channel and is where much of the mesh activity takes place. DM's are only available on the primary channel and it can not be disabled.")
							.font(.callout)
							.padding([.leading,.trailing,.bottom])
						Text("Admin Channel").font(.title2)
						Text("The last channel is the Admin channel and can be used to remotely administer nodes on your mesh, text messages can not be sent over the admin channel.")
							.font(.callout)
							.padding([.leading,.trailing,.bottom])
						Text("Private Channels").font(.title2)
						Text("The other six channels can be used for private group converations. Each of these groups has its own encryption key.")
							.font(.callout)
							.padding([.leading,.trailing,.bottom])
						Text("From this view your primary channel and mesh settings are always shared in the generated QR code and you can toggle to include your admin channel and any private groups you want the person you are sharing with to have access to.")
							.font(.callout)
							.padding([.leading,.trailing,.bottom])
						Divider()
					}
					.padding()
					.presentationDetents([.large])
					.presentationDragIndicator(.automatic)
				}
				.navigationTitle("Generate QR Code")
				.navigationBarTitleDisplayMode(.inline)
				.navigationBarItems(trailing:
										
				ZStack {
					
					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
				})
				.onAppear {
					
					if self.initialLoad{
						
						self.bleManager.context = context
						
						self.initialLoad = false
						GenerateChannelSet()
					}
				}
			}
			.navigationViewStyle(StackNavigationViewStyle())
		}
	}
	func GenerateChannelSet() {
	
		var loRaConfig = Config.LoRaConfig()
		loRaConfig.region =  RegionCodes(rawValue: Int(node!.loRaConfig!.regionCode))!.protoEnumValue()
		loRaConfig.modemPreset = ModemPresets(rawValue: Int(node!.loRaConfig!.modemPreset))!.protoEnumValue()
		loRaConfig.bandwidth = UInt32(node!.loRaConfig!.bandwidth)
		loRaConfig.spreadFactor = UInt32(node!.loRaConfig!.spreadFactor)
		loRaConfig.codingRate = UInt32(node!.loRaConfig!.codingRate)
		loRaConfig.frequencyOffset = node!.loRaConfig!.frequencyOffset
		loRaConfig.hopLimit = UInt32(node!.loRaConfig!.hopLimit)
		loRaConfig.txEnabled = node!.loRaConfig!.txEnabled
		loRaConfig.txPower = node!.loRaConfig!.txPower
		loRaConfig.channelNum = UInt32(node!.loRaConfig!.channelNum)
		
		channelSet.loraConfig = loRaConfig
		
		for ch in node!.myInfo!.channels!.array as! [ChannelEntity] {
			print(ch)
			if ch.role > 0 {
				var channelSettings = ChannelSettings()
				channelSettings.name = ch.name!
				channelSettings.psk = ch.psk ?? Data()
				channelSettings.id = UInt32(ch.id)
				channelSettings.uplinkEnabled = ch.uplinkEnabled
				channelSettings.downlinkEnabled = ch.downlinkEnabled
				channelSet.settings.append(channelSettings)
			}
		}
		
		let settingsString = try! channelSet.serializedData().base64EncodedString(options: [.endLineWithLineFeed])
		channelsUrl =  "https://www.meshtastic.org/e/#" + settingsString.dropLast(2)
	}
}
