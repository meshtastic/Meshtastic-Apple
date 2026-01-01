//
//  Tools.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 12/31/25.
//

import SwiftUI
import CoreNFC
import MeshtasticProtobufs
import OSLog

struct Tools: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.managedObjectContext) var context

	@StateObject private var nfcReader = NFCReader()

	var connectedNode: NodeInfoEntity? {
		if let num = accessoryManager.activeDeviceNum {
			return getNodeInfo(id: num, context: context)
		}
		return nil
	}

	var qrString: String {
		var contact = SharedContact()
		contact.nodeNum = UInt32(connectedNode?.num ?? 0)
		contact.user = connectedNode?.toProto().user ?? User()
		contact.manuallyVerified = true

		do {
			let contactString = try contact.serializedData().base64EncodedString()
			return "https://meshtastic.org/v/#" + contactString.base64ToBase64url()
		} catch {
			Logger.services.error("Error serializing contact: \(error)")
			return ""
		}
	}

	var body: some View {
		VStack{
			List {
				Section(header: Text("Create Node Contact NFC Tag")) {
					if let node = connectedNode {
						Text("Node Name: \(node.user?.longName ?? "Unknown")")
						
						Button {
							nfcReader.scan(theActualData: qrString)
						} label: {
							Label("Write Contact to NFC Tag", systemImage: "tag")
						}
						.disabled(qrString.isEmpty)
					}
				}
			}
		}
		.navigationTitle("Tools")
		.navigationBarTitleDisplayMode(.inline)
	}
}

#Preview {
	Tools()
}

final class NFCReader: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {

	private let logger = Logger(subsystem: "org.meshtastic.app", category: "NFC")
	private var payloadString = ""
	private var session: NFCNDEFReaderSession?

	func scan(theActualData: String) {
		payloadString = theActualData

		session = NFCNDEFReaderSession(
			delegate: self,
			queue: nil,
			invalidateAfterFirstRead: false
		)

		session?.alertMessage = "Hold your iPhone near the NFC tag."
		session?.begin()
	}

	func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
		logger.debug("NFC session became active")
	}

	func readerSession(_ session: NFCNDEFReaderSession,
					   didInvalidateWithError error: Error) {
		logger.error("NFC session invalidated: \(error.localizedDescription)")
	}

	func readerSession(_ session: NFCNDEFReaderSession,
					   didDetectNDEFs messages: [NFCNDEFMessage]) {
	}

	func readerSession(_ session: NFCNDEFReaderSession,
					   didDetect tags: [NFCNDEFTag]) {

		guard tags.count == 1, let tag = tags.first else {
			session.alertMessage = "More than one tag detected. Please present only one."
			DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
				session.restartPolling()
			}
			return
		}

		session.connect(to: tag) { error in
			if let error {
				self.logger.error("Failed to connect to tag: \(error.localizedDescription)")
				session.alertMessage = "Failed to connect to tag."
				session.invalidate()
				return
			}

			tag.queryNDEFStatus { status, _, error in
				if let error {
					self.logger.error("Failed to query NDEF status: \(error.localizedDescription)")
					session.alertMessage = "Failed to read tag."
					session.invalidate()
					return
				}

				switch status {
				case .notSupported:
					self.logger.error("Tag does not support NDEF")
					session.alertMessage = "Tag does not support NDEF."
					session.invalidate()

				case .readOnly:
					self.logger.error("Tag is read-only")
					session.alertMessage = "Tag is read-only."
					session.invalidate()

				case .readWrite:
					guard let payload =
						NFCNDEFPayload.wellKnownTypeURIPayload(
							string: self.payloadString
						) else {
						self.logger.error("Invalid NDEF payload")
						session.alertMessage = "Invalid payload."
						session.invalidate()
						return
					}

					let message = NFCNDEFMessage(records: [payload])

					tag.writeNDEF(message) { error in
						if let error {
							self.logger.error("Failed to write NDEF: \(error.localizedDescription)")
							session.alertMessage = "Failed to write tag."
						} else {
							self.logger.info("Successfully wrote NFC tag")
							session.alertMessage = "NFC tag written successfully."
						}
						session.invalidate()
					}
				}
			}
		}
	}
}
