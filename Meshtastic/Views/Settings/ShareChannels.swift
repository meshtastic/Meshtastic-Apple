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
	
	@State var includeChannel0 = true
	@State var includeChannel1 = true
	@State var includeChannel2 = true
	@State var includeChannel3 = false
	@State var includeChannel4 = false
	@State var includeChannel5 = false
	@State var includeChannel6 = false
	@State var includeChannel7 = true
	
	var node: NodeInfoEntity?
	
	@State private var channelsUrl =  "https://meshtastic.org/e/#test"
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
									Text("Name")
										.font(.caption)
										.fontWeight(.bold)
									Spacer()
								}
								Divider()
								
								ForEach(node!.myInfo!.channels?.array.sorted(by: { ($0 as! ChannelEntity).index < ($1 as! ChannelEntity).index }) as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in

									GridRow {
										Spacer()
										if channel.index == 0 {
											Toggle("Channel 0 Included", isOn: $includeChannel0)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(true)
											Text("Primary Channel")
											
										} else if channel.index == 1 {
											Toggle("Channel 1 Included", isOn: $includeChannel1)
												.toggleStyle(.switch)
												.labelsHidden()
												Text("Public Channel")
										} else if channel.index == 2 {
											Toggle("Channel 2 Included", isOn: $includeChannel2)
												.toggleStyle(.switch)
												.labelsHidden()
										} else if channel.index == 3 {
											Toggle("Channel 3 Included", isOn: $includeChannel3)
												.toggleStyle(.switch)
												.labelsHidden()
										} else if channel.index == 4 {
											Toggle("Channel 4 Included", isOn: $includeChannel4)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(true)
										} else if channel.index == 5 {
											Toggle("Channel 5 Included", isOn: $includeChannel5)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(true)
										} else if channel.index == 6 {
											Toggle("Channel 6 Included", isOn: $includeChannel6)
												.toggleStyle(.switch)
												.labelsHidden()
												.disabled(true)
										} else if channel.index == 7 {
											Toggle("Channel 7 Included", isOn: $includeChannel7)
												.toggleStyle(.switch)
												.labelsHidden()
											Text("Admin Channel")
										}
										if channel.index > 1 && channel.index < 4{
											Text("Private Chat - \(channel.index)")
										}
										if channel.index > 3 && channel.index < 7{
											Text("Channel - \(channel.index)")
										}
										Spacer()
									}
								}
							}
						}
					}
					let qrImage = qrCodeImage.generateQRCode(from: channelsUrl)
					
					VStack {
						
						Divider()
									
						ShareLink("Share QR Code & Link",
							item: Image(uiImage: qrImage),
							subject: Text("Meshtastic Node \(node?.user?.shortName ?? "????") has shared channels with you"),
							message: Text(channelsUrl),
							preview: SharePreview("Meshtastic Node \(node?.user?.shortName ?? "????") has shared channels with you",
												  image: Image(uiImage: qrImage))
						)
						.presentationDetents([.medium, .large])

						Divider()
						
						Image(uiImage: qrImage)
							.resizable()
							.scaledToFit()
							.frame(
								minWidth: smallest * 0.7,
								maxWidth: smallest * 0.7,
								minHeight: smallest * 0.7,
								maxHeight: smallest * 0.7,
								alignment: .top
							)
						
					}
				}
				.navigationTitle("Generate QR Code")
				.navigationBarTitleDisplayMode(.inline)
				.navigationBarItems(trailing:
										
				ZStack {
					
					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
				})
				.onAppear {
					
					self.bleManager.context = context
				}
			}
			.navigationViewStyle(StackNavigationViewStyle())
		}
	}
}
