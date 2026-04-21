//
//  AccessoryManager+TAK.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import MeshtasticProtobufs
import MeshtasticTAK
import OSLog

extension AccessoryManager {

	// MARK: - TAK Server Initialization

	/// Initialize the TAK bridge when connected to a Meshtastic device
	func initializeTAKBridge() {
		let takServer = TAKServerManager.shared

		// Lazily create (or reuse) the bridge so we never clobber state
		// from a previously lazy-initialized instance.
		let bridge = takServer.ensureBridge()
		bridge.context = self.context

		Logger.tak.info("TAK bridge initialized")

		// Start server if enabled
		if takServer.enabled && !takServer.isRunning {
			Task {
				do {
					try await takServer.start()
					Logger.tak.info("TAK Server auto-started on connection")
				} catch {
					Logger.tak.error("Failed to auto-start TAK Server: \(error.localizedDescription)")
				}
			}
		}
	}

	/// Clean up TAK bridge when disconnecting
	func cleanupTAKBridge() {
		// Note: We don't stop the server here - it can continue running
		// even without a Meshtastic connection (for TAK connectivity)
		Logger.tak.info("TAK bridge cleanup")
	}

	// MARK: - Receive TAK Packet from Mesh

	/// Handle incoming ATAK Plugin packet from the mesh network
	/// Forwards to connected TAK clients via the bridge
	func handleATAKPluginPacket(_ packet: MeshPacket) {
		guard case let .decoded(data) = packet.payloadVariant else {
			Logger.tak.warning("Received ATAK packet without decoded payload")
			return
		}

		Logger.tak.debug("Received ATAK packet: \(data.payload.count) bytes from node \(packet.from)")

		// Check if packet is compressed (first bytes 08 01 indicate is_compressed = true)
		// Compressed packets are sent as duplicates of uncompressed ones, so we ignore them
		let payload = data.payload
		if payload.count >= 2 && payload[0] == 0x08 && payload[1] == 0x01 {
			Logger.tak.debug("Ignoring compressed TAKPacket (duplicate of uncompressed)")
			return
		}

		// Parse uncompressed TAKPacket protobuf
		let takPacket: MeshtasticProtobufs.TAKPacket
		do {
			takPacket = try TAKPacket(serializedBytes: payload)
		} catch {
			Logger.tak.warning("Failed to parse TAKPacket from mesh packet: \(error.localizedDescription)")
			Logger.tak.debug("Parse error details: \(error)")
			Logger.tak.debug("Raw payload hex: \(payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
			return
		}

		Logger.tak.info("Received TAKPacket from mesh node \(packet.from)")
		Logger.tak.debug("  hasContact: \(takPacket.hasContact), hasGroup: \(takPacket.hasGroup), hasStatus: \(takPacket.hasStatus)")
		Logger.tak.debug("  payloadVariant: \(String(describing: takPacket.payloadVariant))")

		// Forward to TAK clients via bridge (lazily create if needed)
		Task {
			await TAKServerManager.shared.ensureBridge().broadcastToTAKClients(takPacket, from: packet.from)
		}
	}

	// MARK: - Receive TAK V2 Packet from Mesh (Port 78)

	/// Handle incoming ATAK Plugin V2 packet from the mesh network
	/// Wire format: [flags byte][zstd-compressed TAKPacketV2 protobuf]
	/// Uses TAKPacket-SDK for decompression
	func handleATAKPluginV2Packet(_ packet: MeshPacket) {
		guard case let .decoded(data) = packet.payloadVariant else {
			Logger.tak.warning("Received ATAK V2 packet without decoded payload")
			return
		}

		Logger.tak.debug("Received ATAK V2 packet: \(data.payload.count) bytes from node \(packet.from)")

		let wirePayload = data.payload
		guard wirePayload.count >= 2 else {
			Logger.tak.warning("ATAK V2 payload too short: \(wirePayload.count) bytes")
			return
		}

		// Decompress using TAKPacket-SDK
		do {
			let compressor = MeshtasticTAK.TakCompressor()
			let takPacketV2 = try compressor.decompress(wirePayload)

			Logger.tak.info("Decompressed ATAK V2 packet from node \(packet.from): \(takPacketV2.callsign)")

			// Convert TAKPacketV2 → CoT XML via SDK builder, then forward
			// the raw XML directly to TAK clients. Do NOT re-parse through
			// CoTMessage — that strips shape detail elements (link-point
			// vertices, strokeColor, fillColor, etc.) that ATAK needs.
			let builder = MeshtasticTAK.CotXmlBuilder()
			let rawCotXml = builder.build(takPacketV2)
			// Strip the XML declaration and collapse whitespace — TAK clients'
			// TCP streaming parsers expect bare <event>...</event> on a single
			// line, not a formatted XML document with <?xml ...?> prologue.
			let cotXml = rawCotXml
				.replacingOccurrences(of: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>", with: "")
				.replacingOccurrences(of: "\\s*\\n\\s*", with: "", options: .regularExpression)
				.trimmingCharacters(in: .whitespacesAndNewlines)

			// Logger.tak.debug("=== Received CoT XML (mesh, \(cotXml.count) chars) ===")
			// Logger.tak.debug("\(cotXml)")
			// Logger.tak.debug("=== End Raw XML ===")

			Task {
				await TAKServerManager.shared.broadcastRawXml(cotXml)
			}
			Logger.tak.info("Forwarded ATAK V2 to TAK clients (raw XML)")

			// Routes: iTAK ignores b-m-r from TCP streaming. Save as KML
			// data package to Documents/TAK Routes/ for manual import.
			if cotXml.contains("type=\"b-m-r\"") {
				if let (fileName, zipData) = RouteDataPackageGenerator.generateDataPackage(routeXml: cotXml),
				   let savedURL = RouteDataPackageGenerator.saveToDocuments(fileName: fileName, zipData: zipData) {
					Logger.tak.info("Route data package saved: \(savedURL.path)")
					let routeName = RouteDataPackageGenerator.extractRouteName(routeXml: cotXml) ?? "Unknown Route"
					Task { @MainActor in
						let mgr = LocalNotificationManager()
						mgr.notifications.append(Notification(
							id: UUID().uuidString,
							title: "Route Received",
							subtitle: routeName,
							content: "Saved to Files → Meshtastic → TAK Routes. Open in iTAK to import."
						))
						mgr.schedule()
					}
				} else {
					Logger.tak.warning("Route data package generation failed for b-m-r")
				}
			}
		} catch {
			Logger.tak.error("Failed to decompress ATAK V2 packet: \(error.localizedDescription)")
		}
	}

	// MARK: - Send TAK V2 Packet to Mesh

	/// Send a compressed TAK V2 wire payload to the mesh
	func sendTAKV2Packet(_ wirePayload: Data, channel: UInt32 = 0) async throws {
		guard let activeConnection else {
			throw AccessoryError.connectionFailed("Not connected to Meshtastic device")
		}
		guard let deviceNum = activeConnection.device.num else {
			throw AccessoryError.connectionFailed("No device number available")
		}

		var dataMessage = DataMessage()
		dataMessage.portnum = .atakPluginV2  // Port 78
		dataMessage.payload = wirePayload

		var meshPacket = MeshPacket()
		meshPacket.to = 0xFFFFFFFF  // Broadcast
		meshPacket.from = UInt32(deviceNum)
		meshPacket.channel = channel
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.decoded = dataMessage

		var toRadio = ToRadio()
		toRadio.packet = meshPacket

		try await send(toRadio, debugDescription: "Sending TAKPacket V2 to mesh")
		Logger.tak.info("Sent TAK V2 packet to mesh (port=78, channel=\(channel), size=\(wirePayload.count) bytes)")
	}

	/// Send a CoT message to the mesh using the V2 protocol
	func sendCoTToMeshV2(_ cotXml: String, channel: UInt32 = 0) async throws {
		// Full raw CoT XML being compressed and radio'd out to the mesh.
		// This is the exact event the V2 receiver on the other end will
		// see after TakCompressor.decompress + CotXmlBuilder.build, so
		// logging here closes the debugging loop with the "Received CoT
		// XML (mesh, ...)" line in handleATAKPluginV2Packet.
		// Logger.tak.debug("=== Sending CoT XML (mesh, \(cotXml.count) chars) ===")
		// Logger.tak.debug("\(cotXml)")
		// Logger.tak.debug("=== End Raw XML ===")

		// Extend stale time for static objects (routes, shapes, markers) that
		// may arrive over LoRa mesh past their original TTL. iTAK uses 2-min
		// stale for routes; ATAK uses 24h. 5 min minimum ensures the object
		// survives multi-hop mesh delivery and renders on the receiving end.
		let freshXml = Self.ensureMinimumStaleForMesh(cotXml)
		let strippedXml = Self.stripNonEssentialElements(freshXml)
		let parser = MeshtasticTAK.CotXmlParser()
		let packet = parser.parse(strippedXml)
		let compressor = MeshtasticTAK.TakCompressor()
		// compressWithRemarksFallback preserves <remarks> text when the
		// compressed packet fits under the LoRa MTU, and strips remarks
		// automatically if needed to fit. Returns nil if even without
		// remarks the packet exceeds the limit.
		let maxWirePayloadBytes = 225
		guard let wirePayload = try compressor.compressWithRemarksFallback(packet, maxWireBytes: maxWirePayloadBytes) else {
			Logger.tak.warning("Dropping oversized TAK packet: max=\(maxWirePayloadBytes)B xml=\(min(cotXml.count, 1024)) chars: \(String(cotXml.prefix(1024)))")
			return
		}
		Logger.tak.info("TAK → mesh: xml=\(cotXml.count)B → stripped=\(strippedXml.count)B → compressed=\(wirePayload.count)B")

		try await sendTAKV2Packet(wirePayload, channel: channel)
	}

	/// Ensure static CoT types (routes, shapes, markers) have at least 5 minutes
	/// of stale time remaining. iTAK uses 2-min stale for routes while ATAK uses
	/// 24h. Over LoRa mesh with multi-hop relay, a short stale means the object
	/// arrives already expired and ATAK silently discards it. PLI and GeoChat are
	/// left untouched — their stale times are semantically meaningful.
	private static let minimumMeshStaleTTL: TimeInterval = 900 // 15 minutes
	private static let staticCoTTypePrefixes = ["b-m-r", "u-d-", "b-m-p-"]
	private static let isoFormatter: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime]
		return f
	}()
	private static let isoFormatterFrac: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	private static func ensureMinimumStaleForMesh(_ xml: String) -> String {
		// Quick check: does the type match a static prefix?
		guard let typeRe = try? NSRegularExpression(pattern: #"<event\s[^>]*\btype="([^"]*)""#),
			  let typeMatch = typeRe.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
			  let typeRange = Range(typeMatch.range(at: 1), in: xml) else { return xml }
		let type = String(xml[typeRange])
		guard staticCoTTypePrefixes.contains(where: { type.hasPrefix($0) }) else { return xml }

		// Extract current stale timestamp
		guard let staleRe = try? NSRegularExpression(pattern: #"\bstale="([^"]*)""#),
			  let staleMatch = staleRe.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
			  let staleValueRange = Range(staleMatch.range(at: 1), in: xml),
			  let staleFullRange = Range(staleMatch.range, in: xml) else { return xml }
		let staleStr = String(xml[staleValueRange])
		guard let staleDate = isoFormatter.date(from: staleStr) ?? isoFormatterFrac.date(from: staleStr) else { return xml }

		let now = Date()
		let remaining = staleDate.timeIntervalSince(now)
		guard remaining < minimumMeshStaleTTL else { return xml }

		// Extend to now + 5 min
		let newStale = now.addingTimeInterval(minimumMeshStaleTTL)
		let newStaleStr = isoFormatter.string(from: newStale)
		var result = xml
		result.replaceSubrange(staleFullRange, with: "stale=\"\(newStaleStr)\"")
		Logger.tak.info("Extended stale for \(type): \(staleStr) → \(newStaleStr) (was \(Int(remaining))s remaining, now \(Int(minimumMeshStaleTTL))s)")
		return result
	}

	/// Strip non-essential XML elements before mesh compression to save wire bytes.
	/// These elements add 100-200 bytes but aren't needed for rendering shapes,
	/// routes, chats, or markers on the receiving end.
	private static func stripNonEssentialElements(_ xml: String) -> String {
		var result = xml
		// Elements to strip — order doesn't matter, regex handles self-closing and paired
		let patterns = [
			"<takv[^>]*/>",                             // TAK version info
			"<takv[^>]*>.*?</takv>",                     // TAK version (paired)
			"<voice[^>]*/>",                             // voice chat state
			"<voice[^>]*>.*?</voice>",
			"<marti[^>]*/>",                             // empty marti
			"<marti[^>]*>.*?</marti>",
			"<__geofence[^>]*/>",                        // geofence config
			"<__geofence[^>]*>.*?</__geofence>",
			"<tog[^>]*/>",                               // toggle state
			"<archive[^>]*/>",                           // archive marker
			"<__shapeExtras[^>]*/>",                     // shape extras
			"<__shapeExtras[^>]*>.*?</__shapeExtras>",
			"<creator[^>]*/>",                           // creator info
			"<creator[^>]*>.*?</creator>",
			"<remarks[^>]*/>",                            // empty remarks (self-closing)
			"<remarks[^>]*></remarks>",                   // empty remarks (paired)
			"<strokeStyle[^>]*/>",                       // stroke style (SDK uses color fields)
			"<precisionlocation[^>]*/>",                 // precision location metadata
			"<precisionlocation[^>]*>.*?</precisionlocation>",
			"<precisionLocation[^>]*/>",                 // iTAK camelCase variant
			"<precisionLocation[^>]*>.*?</precisionLocation>",
		]
		for pattern in patterns {
			if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
				result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
			}
		}
		// Strip any attribute with value "???" — unknown/placeholder metadata
		if let unknownAttr = try? NSRegularExpression(pattern: #"\s+\w+\s*=\s*"\?{3}""#) {
			result = unknownAttr.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
		}
		// Strip specific display-only attributes the SDK doesn't use
		let attrPatterns = [
			#"\s+routetype\s*=\s*"[^"]*""#,      // route display type
			#"\s+order\s*=\s*"[^"]*""#,           // checkpoint order label
			#"\s+color\s*=\s*"[^"]*""#,           // link_attr color (SDK uses strokeColor)
			#"\s+access\s*=\s*"[^"]*""#,          // access control
			#"\s+callsign\s*=\s*"""#,             // empty callsign
			#"\s+phone\s*=\s*"""#,                // empty phone
		]
		for pattern in attrPatterns {
			if let regex = try? NSRegularExpression(pattern: pattern) {
				result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
			}
		}
		// Strip uid from route waypoint <link> elements — UIDs are full 36-char
		// UUIDs that cost ~40 bytes each in the proto wire format. The receiving
		// TAK client derives its own UIDs, so these are pure overhead. Only targets
		// <link> elements with a point= attribute (route waypoints / shape vertices).
		if let routeLinkRe = try? NSRegularExpression(pattern: #"<link\s[^>]*\bpoint="[^"]*"[^>]*/>"#),
		   let uidAttrRe = try? NSRegularExpression(pattern: #"\s+uid="[^"]*""#) {
			let matches = routeLinkRe.matches(in: result, range: NSRange(result.startIndex..., in: result))
			for match in matches.reversed() {
				if let range = Range(match.range, in: result) {
					let linkStr = String(result[range])
					let stripped = uidAttrRe.stringByReplacingMatches(
						in: linkStr,
						range: NSRange(linkStr.startIndex..., in: linkStr),
						withTemplate: ""
					)
					result.replaceSubrange(range, with: stripped)
				}
			}
		}
		return result
	}
}
