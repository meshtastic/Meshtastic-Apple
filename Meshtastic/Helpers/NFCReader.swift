//
//  NFCReader.swift
//  Meshtastic
//
//  NDEF tag read/write sessions for sharing and importing Meshtastic
//  contact and channel URLs. Promoted out of Tools.swift so every share
//  surface can reuse the same session handling.
//

import SwiftUI
import OSLog
#if !targetEnvironment(macCatalyst)
import CoreNFC
#endif

#if !targetEnvironment(macCatalyst)
@available(iOS 18, *)
final class NFCReader: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {

	/// The two session modes are mutually exclusive so a read session can
	/// never write a stale payload and a write session ignores tag contents.
	private enum Mode {
		case write(payload: String)
		case read(onURL: (URL) -> Void)
	}

	private let logger = Logger(subsystem: "org.meshtastic.app", category: "NFC")
	private var mode: Mode?
	private var session: NFCNDEFReaderSession?

	/// True when this device has NFC reading hardware available.
	/// Callers should hide NFC affordances entirely when this is false.
	static var isAvailable: Bool {
		NFCNDEFReaderSession.readingAvailable
	}

	func scan(theActualData: String) {
		// Tear down any in-flight session so a stale one can't race the new mode.
		session?.invalidate()
		mode = .write(payload: theActualData)

		session = NFCNDEFReaderSession(
			delegate: self,
			queue: nil,
			invalidateAfterFirstRead: false
		)

		session?.alertMessage = String(localized: "Hold your iPhone near the NFC tag.")
		session?.begin()
	}

	/// Starts a read session and calls `onURL` (on the main actor) with the
	/// first https/meshtastic URL found on the tag.
	func scanToRead(onURL: @escaping (URL) -> Void) {
		// Tear down any in-flight session so a stale one can't race the new mode.
		session?.invalidate()
		mode = .read(onURL: onURL)

		session = NFCNDEFReaderSession(
			delegate: self,
			queue: nil,
			invalidateAfterFirstRead: true
		)

		session?.alertMessage = String(localized: "Hold your iPhone near the Meshtastic NFC tag.")
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
		guard case .read(let onURL) = mode else { return }
		deliverFirstURL(from: messages, session: session, onURL: onURL)
	}

	func readerSession(_ session: NFCNDEFReaderSession,
	                   didDetect tags: [NFCNDEFTag]) {

		guard tags.count == 1, let tag = tags.first else {
			session.alertMessage = String(localized: "More than one tag detected. Please present only one.")
			DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
				session.restartPolling()
			}
			return
		}

		session.connect(to: tag) { error in
			if let error {
				self.logger.error("Failed to connect to tag: \(error.localizedDescription)")
				session.alertMessage = String(localized: "Failed to connect to tag.")
				session.invalidate()
				return
			}

			switch self.mode {
			case .write(let payload):
				self.write(payload: payload, to: tag, session: session)
			case .read(let onURL):
				self.read(from: tag, session: session, onURL: onURL)
			case nil:
				self.logger.error("NFC tag detected without an active mode")
				session.invalidate()
			}
		}
	}

	// MARK: - Write

	private func write(payload payloadString: String, to tag: NFCNDEFTag, session: NFCNDEFReaderSession) {
		tag.queryNDEFStatus { status, capacity, error in
			if let error {
				self.logger.error("Failed to query NDEF status: \(error.localizedDescription)")
				session.alertMessage = String(localized: "Failed to read tag.")
				session.invalidate()
				return
			}
			self.logger.debug("Tag NDEF status: \(String(describing: status)), capacity: \(capacity) bytes")

			switch status {
			case .notSupported:
				self.logger.error("Tag does not support NDEF")
				session.alertMessage = String(localized: "Tag does not support NDEF.")
				session.invalidate()

			case .readOnly:
				self.logger.error("Tag is read-only")
				session.alertMessage = String(localized: "Tag is read-only.")
				session.invalidate()

			case .readWrite:
				guard let payload =
					NFCNDEFPayload.wellKnownTypeURIPayload(
						string: payloadString
					) else {
					self.logger.error("Invalid NDEF payload")
					session.alertMessage = String(localized: "Invalid payload.")
					session.invalidate()
					return
				}

				let message = NFCNDEFMessage(records: [payload])

				guard message.length <= capacity else {
					self.logger.error("Payload (\(message.length) bytes) exceeds tag capacity (\(capacity) bytes)")
					session.alertMessage = String(localized: "Tag too small to hold this data.")
					session.invalidate()
					return
				}

				tag.writeNDEF(message) { error in
					if let error {
						self.logger.error("Failed to write NDEF: \(error.localizedDescription)")
						session.alertMessage = String(localized: "Failed to write tag.")
					} else {
						self.logger.info("Successfully wrote NFC tag")
						session.alertMessage = String(localized: "NFC tag written successfully.")
					}
					session.invalidate()
				}

			@unknown default:
				self.logger.error("Unsupported NDEF status")
				session.alertMessage = String(localized: "Unsupported tag status.")
				session.invalidate()
			}
		}
	}

	// MARK: - Read

	private func read(from tag: NFCNDEFTag, session: NFCNDEFReaderSession, onURL: @escaping (URL) -> Void) {
		tag.readNDEF { message, error in
			if let error {
				self.logger.error("Failed to read NDEF: \(error.localizedDescription)")
				session.alertMessage = String(localized: "Failed to read tag.")
				session.invalidate()
				return
			}
			guard let message else {
				session.alertMessage = String(localized: "No data found on this tag.")
				session.invalidate()
				return
			}
			self.deliverFirstURL(from: [message], session: session, onURL: onURL)
		}
	}

	private func deliverFirstURL(from messages: [NFCNDEFMessage], session: NFCNDEFReaderSession, onURL: @escaping (URL) -> Void) {
		for message in messages {
			for record in message.records {
				guard let url = self.url(from: record) else { continue }
				// Only deliver URLs the app can actually import: contact links
				// (meshtastic.org/v/#) and channel links (meshtastic.org/e/ or
				// meshtastic://e). Anything else falls through to the failure
				// message below instead of a success HUD followed by silence.
				guard ContactURLHandler.canHandle(url) || MeshtasticChannelURL.canHandle(url) else { continue }
				logger.info("Read NFC tag URL")
				session.alertMessage = String(localized: "NFC tag read successfully.")
				session.invalidate()
				Task { @MainActor in
					onURL(url)
				}
				return
			}
		}
		logger.error("No Meshtastic URL found on tag")
		session.alertMessage = String(localized: "No Meshtastic link found on this tag.")
		session.invalidate()
	}

	private func url(from record: NFCNDEFPayload) -> URL? {
		if let url = record.wellKnownTypeURIPayload() {
			return url
		}
		// Well-known Text records carry a status byte and language code before the
		// text, so decode them properly rather than reading `payload` as raw UTF-8.
		let (text, _) = record.wellKnownTypeTextPayload()
		if let text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
			return url
		}
		// Fall back to plain UTF-8 payloads that hold a URL string.
		if let string = String(data: record.payload, encoding: .utf8),
		   let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
			return url
		}
		return nil
	}
}
#endif

#if !targetEnvironment(macCatalyst)
/// A "Write to NFC Tag" button with a plain-language caption underneath.
/// Callers must additionally gate on `#available(iOS 18, *)`; the button
/// hides itself entirely on devices without NFC hardware.
@available(iOS 18, *)
struct NFCWriteButton: View {
	let payload: String
	let caption: LocalizedStringKey
	@StateObject private var nfcReader = NFCReader()

	var body: some View {
		if NFCReader.isAvailable {
			VStack(spacing: 8) {
				Button {
					nfcReader.scan(theActualData: payload)
				} label: {
					Label("Write to NFC Tag", systemImage: "tag")
				}
				.disabled(payload.isEmpty)
				Text(caption)
					.font(.caption)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
			}
		}
	}
}
#endif
