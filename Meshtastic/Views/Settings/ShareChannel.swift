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

struct ShareChannel: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	
	var node: NodeInfoEntity?
	
	@State private var text =  "https://meshtastic.org/E/#test"
	var qrCodeImage = QrCodeImage()
	
	var body: some View {
		
		VStack {
			
			GeometryReader { bounds in
				
				let smallest = min(bounds.size.width, bounds.size.height)
				
				ScrollView {

					VStack {
						Text("Scan the QR code below with the Apple or Android device you would like to share your channel settings with.")
							.fixedSize(horizontal: false, vertical: true)
							.font(.callout)
						
						let image = qrCodeImage.generateQRCode(from: text)
						Image(uiImage: image)
							.resizable()
							.scaledToFit()
							.frame(
								minWidth: smallest * 0.9,
								maxWidth: smallest * 0.9,
								minHeight: smallest * 0.9,
								maxHeight: smallest * 0.9,
								alignment: .center
							)
						Spacer()
						Text("Channel Name (Long/Slow)").font(.title)
						Spacer()
					}
					.frame(width: bounds.size.width, height: bounds.size.height)
				}
			}
			.navigationTitle("Share Channel")
			.navigationBarTitleDisplayMode(.automatic)
			.navigationBarItems(trailing:

				ZStack {

				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
			})
			.onAppear {

				self.bleManager.context = context
				let i: UInt32 = 1;
//				while i < 9 { // this should actually loop over MyNodeInfo.maxChannels to get all channels
					print("requesting channel",i)
					let resp = self.bleManager.getChannel(channelIndex: i, wantResponse: true)
					print("resp from getChannel", resp)
//					i+=1;
//				}
			}
			
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
