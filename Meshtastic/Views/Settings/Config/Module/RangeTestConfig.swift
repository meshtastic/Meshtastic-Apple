//
//  TelemetryConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import SwiftUI

struct RangeTestConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges = false
	
	@State var enabled = false
	@State var sender = false
	@State var save = false
	
	var body: some View {
		
		VStack {

			Form {
				
				Section(header: Text("Options")) {
				
					Toggle(isOn: $enabled) {

						Label("Enabled", systemImage: "figure.walk")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $sender) {

						Label("Sender", systemImage: "paperplane")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("This device will send out range test messages.")
						.font(.caption)
					
					Toggle(isOn: $save) {

						Label("Save", systemImage: "square.and.arrow.down.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Text("Saves a CSV with the range test message details, only available on ESP32 devices with a web server.")
						.font(.caption)
				}
				
			}
			
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
				Button("Save Range Test Module Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
						
				var rtc = ModuleConfig.RangeTestConfig()
					rtc.enabled = enabled
					rtc.save = save
					rtc.sender = sender ? 1 : 0
					
					if bleManager.saveRangeTestModuleConfig(config: rtc, destNum: bleManager.connectedPeripheral.num, wantResponse: false) {
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						
					} else {
						
					}
				}
			}
			
			.navigationTitle("Range Test Config")
			.navigationBarItems(trailing:

				ZStack {

					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?????")
			})
			.onAppear {

				if self.initialLoad{
					
					self.bleManager.context = context
//					self.enabled = node.rangeTestConfig?.enabled ?? false
//					self.save = node.rangeTestConfig?.save ?? false
//					
//					if node.rangeTestConfig?.sender != nil {
//						
//						self.sender = node.rangeTestConfig!.sender == 1 ? true : false
//						
//					} else {
//						self.sender = false
//					}
//					self.sender = node.rangeTestConfig?.sender != nil
					self.hasChanges = false
					self.initialLoad = false
				}
			}
			.onChange(of: enabled) { newEnabled in
				
				//if newEnabled != node.rangeTestConfig!.enabled {
					
					hasChanges = true
				//}
			}
			.onChange(of: save) { newSave in
				
				//if newSave != node.rangeTestConfig!.save {
					
					hasChanges = true
				//}
			}
			.onChange(of: sender) { newSender in
				
				hasChanges = true
			}
			.navigationViewStyle(StackNavigationViewStyle())
		}
	}
}
