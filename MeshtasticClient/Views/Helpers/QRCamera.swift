//
//  QRCamera.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 4/8/22.
//

import SwiftUI
import CarBode
import AVFoundation

struct cameraFrame: Shape {
	func path(in rect: CGRect) -> Path {
		Path { path in
			let width = rect.width
			let height = rect.height
			
			path.addLines( [
				
				CGPoint(x: 0, y: height * 0.25),
				CGPoint(x: 0, y: 0),
				CGPoint(x:width * 0.25, y:0)
			])
			
			path.addLines( [
				
				CGPoint(x: width * 0.75, y: 0),
				CGPoint(x: width, y: 0),
				CGPoint(x:width, y:height * 0.25)
			])
			
			path.addLines( [
				
				CGPoint(x: width, y: height * 0.75),
				CGPoint(x: width, y: height),
				CGPoint(x:width * 0.75, y: height)
			])
			
			path.addLines( [
				
				CGPoint(x:width * 0.25, y: height),
				CGPoint(x:0, y: height),
				CGPoint(x:0, y:height * 0.75)
			   
			])
			
		}
	}
}

struct QRCamera: View {
	@State var barcodeValue = ""
	@State var torchIsOn = false
	@State var showingAlert = false
	@State var cameraPosition = AVCaptureDevice.Position.back

	var body: some View {
		VStack {
			Text("QRCode Scanner")

			Spacer()
			
			if cameraPosition == .back{
				Text("Using back camera")
			}else{
				Text("Using front camera")
			}
			
			Button(action: {
				if cameraPosition == .back {
					cameraPosition = .front
				}else{
					cameraPosition = .back
				}
			}) {
				if cameraPosition == .back{
					Text("Switch Camera to Front")
				}else{
					Text("Switch Camera to Back")
				}
			}
			
			
			Button(action: {
				self.torchIsOn.toggle()
			}) {
				Text("Toggle Torch Light")
			}

			Spacer()
			
			CBScanner(
				supportBarcode: .constant([.qr, .code128]),
				torchLightIsOn: $torchIsOn,
				cameraPosition: $cameraPosition,
				mockBarCode: .constant(BarcodeData(value:"My Test Data", type: .qr))
			){
				print("BarCodeType =",$0.type.rawValue, "Value =",$0.value)
				barcodeValue = $0.value
			}
			onDraw: {
				print("Preview View Size = \($0.cameraPreviewView.bounds)")
				print("Barcode Corners = \($0.corners)")
				
				let lineColor = UIColor.green
				let fillColor = UIColor(red: 0, green: 1, blue: 0.2, alpha: 0.4)
				//Draw Barcode corner
				$0.draw(lineWidth: 1, lineColor: lineColor, fillColor: fillColor)
				
			}.frame(minWidth: 0, maxWidth: .infinity, minHeight: 400, maxHeight: 400, alignment: .topLeading)
				.overlay(cameraFrame()
							.stroke(lineWidth: 5)
							.frame(width: 500, height: 250)
							.foregroundColor(.blue))
			
			Spacer()

			Text(barcodeValue)
			
			Spacer()

		}.alert(isPresented: $showingAlert) {
			Alert(title: Text("Found Barcode"), message: Text("\(barcodeValue)"), dismissButton: .default(Text("Close")))
		}
	}
}

struct ModalScannerView_Previews: PreviewProvider {
	static var previews: some View {
		QRCamera()
	}
}

