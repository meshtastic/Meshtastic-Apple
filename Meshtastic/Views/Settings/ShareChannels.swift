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
	
	@State var channel1Enabled = true
	
	var node: NodeInfoEntity?
	
	@State private var text =  "https://meshtastic.org/E/#test"
	var qrCodeImage = QrCodeImage()
	
	var body: some View {
		
		VStack {
			
			GeometryReader { bounds in
				
				let smallest = min(bounds.size.width, bounds.size.height)
				
				ScrollView {
					
					Text("The current LoRa configuration will also be shared.")
						.fixedSize(horizontal: false, vertical: true)
						.font(.callout)
						.padding(.bottom)
					
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
									Text("Role")
										.font(.caption)
										.fontWeight(.bold)
									Spacer()
								}
								Divider()
								
								ForEach(node!.myInfo!.channels?.array.sorted(by: { ($0 as! ChannelEntity).index < ($1 as! ChannelEntity).index }) as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in

									GridRow {
										Spacer()
										Toggle("Channel 1 Enabled", isOn: $channel1Enabled)
											.toggleStyle(.switch)
											.labelsHidden()
										
										Text("Channel - \(channel.index)")
										Spacer()
									}
								}
							}
						}
					}
					
					VStack {
						
						Divider()
						ShareLink(
							item: text,
							preview: SharePreview(
								"Meshtastic Channel Settings From Node \(node?.user?.shortName ?? "????")",
								image: Image(systemName: "qrcode")
							)
						)
						.presentationDetents([.large, .large])
						.font(.title3)
						Divider()
					}
					
					VStack {
						
						let image = qrCodeImage.generateQRCode(from: text)
						Image(uiImage: image)
							.resizable()
							.scaledToFit()
							.frame(
								minWidth: smallest * 0.8,
								maxWidth: smallest * 0.8,
								minHeight: smallest * 0.8,
								maxHeight: smallest * 0.8,
								alignment: .center
							)
						
						Divider()
						
						
						VStack {
							
//							if node != nil {
//
//								ForEach(node!.myInfo!.channels?.array.sorted(by: { ($0 as! ChannelEntity).index < ($1 as! ChannelEntity).index }) as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in
//
//									VStack{
//
//										Grid{
//
//											GridRow {
//												Text("Include")
//												Image(systemName: "globe")
//											}
//											GridRow {
//												Toggle("Channel 1 Enabled", isOn: $channel1Enabled)
//													.toggleStyle(.switch)
//													.labelsHidden()
//												Text("World")
//											}
//										}
//									}
//									HStack {
//
//
//										Text("Channel: \(channel.index) Name: \(channel.name ?? "EMPTY") Role: \(channel.role)")
//									}
//								}
//							}
						}
						.frame(width: bounds.size.width, height: bounds.size.height)
					}
				}
				.navigationTitle("Share Channels")
				.navigationBarTitleDisplayMode(.automatic)
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
