//
//  User.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/27/22.
//
import SwiftUI

struct UserConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity
	
	@State private var isPresentingFactoryResetConfirm: Bool = false
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges = false
	
	@State var shortName = ""
	@State var longName = ""
	
	var body: some View {
			
		VStack {

			Form {
				
				Section(header: Text("USER DETAILS")) {

					HStack {
						Label("Long Name", systemImage: "person.crop.rectangle.fill")
						TextField("Long Name", text: $longName)
							.onChange(of: longName, perform: { value in

								let totalBytes = longName.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 40 {

									let firstNBytes = Data(longName.utf8.prefix(40))
							
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										
										// Set the longName back to the last place where it was the right size
										longName = maxBytesString
									}
								}
							})
							.onChange(of: shortName, perform: { value in

								let totalBytes = shortName.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 5 {

									let firstNBytes = Data(shortName.utf8.prefix(5))
							
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										
										// Set the shortName back to the last place where it was the right size
										shortName = maxBytesString
									}
								}
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					.disableAutocorrection(true)
					.listRowSeparator(.visible)
					
					HStack {
						Label("Short Name", systemImage: "circlebadge.fill")
						TextField("Long Name", text: $shortName)
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					.disableAutocorrection(true)
					.listRowSeparator(.visible)
					
				}

			}
			.disabled(bleManager.connectedPeripheral == nil)
			
			HStack {
				
				Button {
								
					isPresentingSaveConfirm = true
					
				} label: {
					
					Label("Save", systemImage: "square.and.arrow.down")
				}
				.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.confirmationDialog(
					
					"Are you sure?",
					isPresented: $isPresentingSaveConfirm
				) {
					Button("Save User Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
						
						var u = User()
						u.shortName = shortName
						u.longName = longName
						
						if bleManager.saveUser(config: u, destNum: bleManager.connectedPeripheral.num, wantResponse: false) {
							
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
							
						} else {
							
						}
					}
				}
			}
			Spacer()
		}
		
		.navigationTitle("User Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?????")
		})
		.onAppear {

			if self.initialLoad{
				
				self.bleManager.context = context

				self.shortName = node.user!.shortName ?? ""
				self.longName = node.user!.longName ?? ""
				self.hasChanges = false
				self.initialLoad = false
			}
		}
		.onChange(of: shortName) { newShort in
			
			if newShort != node.user!.shortName {
				
				hasChanges = true
			}
		}
		.onChange(of: longName) { newLong in
			
			if newLong != node.user!.longName {
				
				hasChanges = true
			}
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
