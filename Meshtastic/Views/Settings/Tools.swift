//
//  Tools.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 12/31/25.
//

import SwiftUI
import MeshtasticProtobufs
import OSLog

@available(iOS 18, *)
struct Tools: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context

	#if !targetEnvironment(macCatalyst)
	@StateObject private var nfcReader = NFCReader()
	#endif
	@State private var saveChannelLink: SaveChannelLinkData?

	var connectedNode: NodeInfoEntity? {
		if let num = accessoryManager.activeDeviceNum {
			return getNodeInfo(id: num, context: context)
		}
		return nil
	}

	var qrString: String {
		guard let connectedNode = connectedNode else {
			return ""
		}
		// Sharing the connected node (your own node), so manuallyVerified is
		// true — the same rule NodeDetail applies for node.num == activeDeviceNum.
		return ShareContactQR.urlString(for: connectedNode.toProto(), manuallyVerified: true) ?? ""
	}

	var body: some View {
		VStack {
			List {
				#if !targetEnvironment(macCatalyst)
				if NFCReader.isAvailable {
					Section(header: Text("NFC Tags")) {
						if let node = connectedNode {
							Text("Node Name: \(node.user?.longName ?? "Unknown".localized)")
							Button {
								nfcReader.scan(theActualData: qrString)
							} label: {
								Label("Write Contact to NFC Tag", systemImage: "tag")
							}
							.disabled(qrString.isEmpty)
							Text("Hold a writable NFC tag near the top of your iPhone to save your contact to it.")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Button {
							nfcReader.scanToRead { url in
								handleScannedURL(url)
							}
						} label: {
							Label("Scan NFC Tag", systemImage: "wave.3.right.circle")
						}
						Text("Read a Meshtastic tag to add the contact or channel it contains.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				#endif
			}
		}
		.navigationTitle("Tools")
		.navigationBarTitleDisplayMode(.inline)
		.sheet(item: $saveChannelLink) { link in
			SaveChannelQRCode(
				channelSetLink: link.data,
				addChannels: link.add,
				accessoryManager: accessoryManager
			)
			.presentationDetents([.large])
			#if !targetEnvironment(macCatalyst)
			.presentationDragIndicator(.visible)
			#endif
		}
	}

	#if !targetEnvironment(macCatalyst)
	/// Routes a URL read from an NFC tag through the same handlers the app
	/// uses for incoming links: contact URLs go to ContactURLHandler, channel
	/// URLs present the SaveChannelQRCode flow.
	private func handleScannedURL(_ url: URL) {
		if url.absoluteString.lowercased().contains("meshtastic.org/v/#") {
			ContactURLHandler.handleContactUrl(url: url, accessoryManager: accessoryManager)
		} else if MeshtasticChannelURL.canHandle(url) {
			do {
				let channelLink = try MeshtasticChannelURL.parse(url.absoluteString)
				saveChannelLink = SaveChannelLinkData(data: channelLink.payload, add: channelLink.addChannels)
			} catch {
				Logger.services.error("Could not parse channel URL from NFC tag: \(error.localizedDescription, privacy: .public)")
			}
		} else {
			Logger.services.error("NFC tag URL is not a Meshtastic contact or channel link")
		}
	}
	#endif
}

@available(iOS 18, *)
#Preview {
	Tools()
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
