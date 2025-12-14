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
					.buttonStyle(.borderedProminent)
					.disabled(showWarningAlert) // Make sure it can't be tapped till the warning is dismissed.

				case .uploading, .starting, .success:
					VStack(spacing: 20.0) {
						CircularProgressView(progress: dfuViewModel.progress, size: 225.0, subtitleText: dfuViewModel.statusMessage)
						Text(dfuViewModel.rotatingMessage)
							.multilineTextAlignment(.center)

					}.frame(maxHeight: .infinity)
				case .error(let message):
					Text("Error: \(message)")
				}
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

private struct CircularProgressView: View {
	let progress: Double
	var lineWidth: CGFloat = 20
	var size: CGFloat = 150
	var strokeColor: Color = .blue
	var backgroundColor: Color = .gray.opacity(0.2)
	var percentageFontSize: CGFloat = 48.0
	var subtitleText: String = "Complete"
	var showSubtitle: Bool = true
	
	private var isComplete: Bool {
		progress >= 1.0
	}
	
	var body: some View {
		ZStack {
			// Background circle
			Circle()
				.stroke(backgroundColor, lineWidth: lineWidth)
			
			// Progress circle
			Circle()
				.trim(from: 0, to: progress)
				.stroke(isComplete ? .green : strokeColor, style: StrokeStyle(
					lineWidth: lineWidth,
					lineCap: .round
				))
				.rotationEffect(.degrees(-90))
				.animation(.spring(response: 0.6), value: progress)
			
			// Content
			if isComplete {
				ZStack {
					// Optional: filled circle background
					Circle()
						.fill(Color.green.opacity(0.15))
						.frame(width: size * 0.6, height: size * 0.6)
					
					// Checkmark
					Image(systemName: "checkmark.circle.fill")
						.font(.system(size: percentageFontSize * 1.5, weight: .bold))
						.foregroundColor(.green)
				}
				.transition(.scale.combined(with: .opacity))
			} else {
				VStack(spacing: 8) {
					Text("\(Int(progress * 100))%")
						.font(.system(size: percentageFontSize, weight: .bold))
						.foregroundColor(.primary)
						.contentTransition(.numericText())
						.animation(.default, value: progress)
					
					if showSubtitle {
						Text(subtitleText)
							.font(.callout)
							.foregroundColor(.secondary)
					}
				}
				.transition(.scale.combined(with: .opacity))
			}
		}
		.frame(width: size, height: size)
		.animation(.spring(response: 0.5, dampingFraction: 0.7), value: isComplete)
	}
}
