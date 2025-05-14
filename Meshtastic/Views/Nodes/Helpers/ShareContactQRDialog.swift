//  ShareContactQRDialog.swift
//  Meshtastic
//
//  Created by GitHub Copilot on 5/13/25.

import SwiftUI
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif
import CoreData
import MeshtasticProtobufs
import OSLog

struct ShareContactQRDialog: View {
    let node: NodeInfo
    @Environment(\.dismiss) private var dismiss
    
    var qrString: String {
		var contact = SharedContact()
		contact.nodeNum = node.num
		contact.user = node.user
		
        do {
            let contactString = try contact.serializedData().base64EncodedString()
			return ("https://meshtastic.org/v/#" + contactString.base64ToBase64url())
        } catch {
			Logger.services.error("Error serializing contact: \(error)")
            return ""
        }
		
    }
    
    var qrImage: UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(qrString.utf8), forKey: "inputMessage")
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        if let outputImage = filter.outputImage?.transformed(by: transform),
           let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgimg)
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Share Contact QR")
                .font(.title2)
                .padding(.top)
			Text(node.user.longName)
                .font(.headline)
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(radius: 4)
			Text("Scan this QR code to add \(node.user.longName) to another device.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
			ShareLink("Share QR Code & Link",
						item: Image(uiImage: qrImage),
					  subject: Text("Add Meshtastic Node \(node.user.shortName) as a contact"),
					  message: Text(qrString),
					  preview: SharePreview("Add Meshtastic Node \(node.user.shortName) as a contact",
						image: Image(uiImage: qrImage))
			)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
        }
        .padding()
        .frame(maxWidth: 350)
    }
}

#if DEBUG
struct ShareContactQRDialog_Previews: PreviewProvider {
    static var previews: some View {
        var node = NodeInfo()
		node.num = 123456
		var userProto = User()
			userProto.id = "!1234"
			userProto.longName = "Bud"
			userProto.shortName = "Bud"
			userProto.hwModel = HardwareModel(rawValue:1)!;
			userProto.role = Config.DeviceConfig.Role(rawValue: 1)!
			userProto.publicKey = Data()
		node.user = userProto

        return ShareContactQRDialog(node: node)
    }
}
#endif
