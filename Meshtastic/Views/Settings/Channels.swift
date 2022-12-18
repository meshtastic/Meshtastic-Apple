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
	let result = keyData.withUnsafeMutableBytes {
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
	
	var body: some View {
		
		ScrollView {
			if node != nil && node?.myInfo != nil {
				Grid() {
					GridRow {
						Text("Index")
							.font(.caption2)
						Text("name")
							.font(.caption2)
						if sizeCategory <= ContentSizeCategory.extraExtraLarge {
							Text("Up/down link")
							.font(.caption2)
						}
						Text("Edit")
							.font(.caption2)
						Text("Delete")
							.font(.caption2)
					}
					ForEach(node!.myInfo!.channels?.array as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in
						GridRow {
							CircleText(text: String(channel.index), color: .accentColor, circleSize: 32)
							Text(((channel.name!.isEmpty ? "Primary" : channel.name) ?? "Primary").camelCaseToWords())
							if sizeCategory <= ContentSizeCategory.extraExtraLarge {
								HStack {
									if channel.uplinkEnabled {
										Image(systemName: "checkmark.square")
									} else {
										Image(systemName: "square")
									}
									if channel.downlinkEnabled {
										Image(systemName: "checkmark.square")
									} else {
										Image(systemName: "square")
									}
								}
							}
							Button {
								print("Edit Channel")
								
							} label: {
								Label("", systemImage: "square.and.pencil")
							}
							Button(role: .destructive) {
								print("Delete Channel")
								
							} label: {
								Label("", systemImage: "trash")
							}
							.disabled(channel.role == 1)
						}
					}
				}
				if node!.myInfo!.channels?.array.count ?? 0 < 8 {
					
					Button {
						print("Add Channel")
						
					} label: {
						Label("Add Channel", systemImage: "plus.square")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding()
				}
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
