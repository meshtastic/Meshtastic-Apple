//
//  NRFDFUSheet.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/11/25.
//

import SwiftUI

struct NRFDFUSheet: View {
	@Environment(\.dismiss) var dismiss
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State var showWarningAlert = true
	@StateObject private var dfuViewModel = DFUViewModel()
	
	let firmwareToFlash: URL
	
	let alertMessage = """
	You are about to flash new firmware to your device. This process carries risks.  Unsucessful updates may brick the device and require re-flashing the bootloader.

	* Ensure your device is charged.
	* Connect your device to a stable power supply.
	* Keep the device close to your phone.
	* Do not close the app during the update.
	* Verify you have selected the correct firmware for your hardware.

	Note: This will temporarily a disconnect your device during the update.
	"""
	
	var body: some View {
		NavigationView { // Use a NavigationView for a title bar
			VStack(spacing: 20.0) {
				Text("DFU Firmware Update")
					.font(.headline)
				
				Text("Please do not leave this screen until this process is complete.")
					.multilineTextAlignment(.center)
					.padding()
				
				CircularProgressView(progress: dfuViewModel.progress, isIndeterminate: ( self.dfuViewModel.state == .starting), size: 225.0, subtitleText: dfuViewModel.statusMessage)
				
				Group {
					switch dfuViewModel.state {
					case .idle:
						Button("Begin Update") {
							Task {
								// Action for your primary button
								if let connection = accessoryManager.activeConnection?.connection as? BLEConnection {
									let peripheral = await connection.peripheral
									dfuViewModel.startDFU(peripheral: peripheral, zipFileUrl: firmwareToFlash)
								}
							}
						}
						.controlSize(.large)
						.frame(maxWidth: .infinity)
						.cornerRadius(10)
						.buttonStyle(.borderedProminent)
						.disabled(showWarningAlert) // Make sure it can't be tapped till the warning is dismissed.
						
					case .uploading, .starting, .success:
						Text(dfuViewModel.rotatingMessage)
							.multilineTextAlignment(.center)
					case .error(let message):
						Text("Error: \(message)")
					}
				}.frame(minHeight: 250.0)
			}.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					// 2. Create a button that calls dismiss()
					Button("Done") {
						dismiss()
					}.disabled([.starting, .uploading].contains(dfuViewModel.state))
				}
			}
		}.alert("Update Warning", isPresented: $showWarningAlert) {
			// Add buttons here
			Button("I Know What I'm Doing", role: .destructive) { }
			Button("Not Now", role: .cancel) {
				dismiss()
			}
		} message: {
			Text(alertMessage)
		}
		.navigationTitle("Nordic DFU Update")
		.navigationBarTitleDisplayMode(.inline)
		.interactiveDismissDisabled(true)
	}
}

