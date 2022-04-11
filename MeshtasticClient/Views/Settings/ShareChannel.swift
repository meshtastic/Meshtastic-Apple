//
//  Channel.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 4/8/22.
//
import SwiftUI
import CoreData
import CarBode


struct ShareChannel: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	
	
	@State var dataString = "Hello Carbode"
	@State var barcodeType = CBBarcodeView.BarcodeType.qrCode
	@State var rotate = CBBarcodeView.Orientation.up
	
	@State var barcodeImage: UIImage?


	var body: some View {
	
		HStack {
			
			GeometryReader { bounds in
				
				ScrollView {
					
					VStack {
						
						let smallest = min(bounds.size.width, bounds.size.height)

						Text("Channel Name").font(.largeTitle)
						CBBarcodeView(data: $dataString,
							barcodeType: $barcodeType,
							orientation: $rotate)
							{ image in
								self.barcodeImage = image
							}.frame(
								minWidth: smallest * 0.9,
								maxWidth: smallest * 0.9,
								minHeight: smallest * 0.9,
								maxHeight: smallest * 0.9,
								alignment: .topLeading
							)
							.padding(.bottom)
						Text("Channel Details").font(.title)
						
						Text("Some helpful text about how this whole thing works goes here, also could add a share sheet icon and pass the link around.")
						Spacer()
						Text("Some helpful text about how this whole thing works goes here, also could add a share sheet icon and pass the link around.")
					}
				}
			}.padding()
		}
		.navigationTitle("Share Channel")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:

			ZStack {

				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "???")
		})
		.onAppear {

			self.bleManager.context = context
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
