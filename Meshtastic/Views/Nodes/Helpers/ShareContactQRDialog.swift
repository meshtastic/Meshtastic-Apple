//  ShareContactQRDialog.swift
//  Meshtastic
//
//  Created by GitHub Copilot on 5/13/25.

import SwiftUI
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif
import SwiftData
import MeshtasticProtobufs
import OSLog

enum ShareContactQR {
	static let urlPrefix = "https://meshtastic.org/v/#"

	/// Whether there is anything worth sharing for this node.
	///
	/// Carrying the public key is the point of a shared contact — it is what lets the receiving radio
	/// direct message the node. A contact with no key is worse than useless: firmware assigns
	/// `public_key` unconditionally when it applies one, so it clears the key the receiving radio
	/// already held. We refuse those on import, so we must not hand them out either.
	static func canShareContact(for node: NodeInfoEntity) -> Bool {
		node.user?.unmessagable == false && node.user?.publicKey?.isEmpty == false
	}

	static func canShareContact(for node: NodeInfo) -> Bool {
		node.hasUser && !node.user.isUnmessagable && !node.user.publicKey.isEmpty
	}

	static func urlString(for node: NodeInfo, manuallyVerified: Bool) -> String? {
		guard canShareContact(for: node) else { return nil }

		var contact = SharedContact()
		contact.nodeNum = node.num
		contact.user = node.user
		contact.manuallyVerified = manuallyVerified
		do {
			let contactString = try contact.serializedData().base64EncodedString()
			return urlPrefix + contactString.base64ToBase64url()
		} catch {
			Logger.services.error("Error serializing contact: \(error)")
			return nil
		}
	}
}

struct ShareContactQRDialog: View {
	let manuallyVerified: Bool
	let node: NodeInfo
	@Environment(\.dismiss) private var dismiss

	var qrString: String {
		ShareContactQR.urlString(for: node, manuallyVerified: manuallyVerified) ?? ""
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
					  preview: SharePreview(
						"Add Meshtastic Node \(node.user.shortName) as a contact",
						image: Image(uiImage: qrImage)
					  )
			)
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 18, *) {
				NFCWriteButton(
					payload: qrString,
					caption: "Hold a writable NFC tag near the top of your iPhone to share this contact."
				)
			}
			#endif
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
			userProto.hwModel = HardwareModel.tbeam
			userProto.role = Config.DeviceConfig.Role.client
			userProto.publicKey = Data()
		node.user = userProto

        return ShareContactQRDialog(manuallyVerified: false, node: node)
    }
}
#endif
