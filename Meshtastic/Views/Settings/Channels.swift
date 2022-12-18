//
//  ShareChannel.swift
//  MeshtasticApple
//
//  Copyright(c) Garth Vander Houwen 4/8/22.
//
import SwiftUI
import CoreData

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
	@Environment(\.dismiss) private var dismiss
	@Environment(\.sizeCategory) var sizeCategory

	var node: NodeInfoEntity?
	
	@State private var isPresentingEditView = false
	@State private var selectedIndex: Int32 = -1
	
	var body: some View {
		
		NavigationStack {
			List {
				if node != nil && node?.myInfo != nil {
					ForEach(node!.myInfo!.channels?.array as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in
						Button(action:  {
							selectedIndex = channel.index
							isPresentingEditView = true
							print("Tapity tap")
						}) {
							VStack(alignment: .leading) {
								HStack {
									CircleText(text: String(channel.index), color: .accentColor, circleSize: 45, fontSize: 36, brightness: 0.1)
										.padding(.trailing, 5)
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
			if node?.myInfo?.channels?.array.count ?? 0 < 8 {
				
				Button {
					let key = generateChannelKey(size: 32)
					print("Add Channel Key \(key) ")
					
				} label: {
					Label("Add Channel", systemImage: "plus.square")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
			}
		}
		.navigationTitle("Channels")
		.navigationBarItems(trailing:
		ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			bleManager.context = context
		}
	}
}
