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

	// MARK: - Receive ATAK Forwarder Packet from Mesh (Port 257, V1)

	/// Handle incoming `atakForwarder` (port 257) packet from another V1 Apple
	/// peer. Wire format: EXI-compressed CoT XML, possibly fragmented across
	/// multiple packets with Fountain (LT) codes. Reassembly + decompression
	/// happens inside `GenericCoTHandler.handleIncomingForwarderPacket`, which
	/// returns the reconstructed `CoTMessage` once a full transfer arrives
	/// (or `nil` for intermediate fragments). Firmware and Android never
	/// decode this — it's Apple ↔ Apple only.
	func handleATAKForwarderPacket(_ packet: MeshPacket) {
		guard case let .decoded(data) = packet.payloadVariant else {
			Logger.tak.warning("Received ATAK_FORWARDER packet without decoded payload")
			return
		}

		Logger.tak.debug("Received ATAK_FORWARDER packet: \(data.payload.count) bytes from node \(packet.from)")

		let packetCopy = packet
		let accessoryManagerRef = self
		Task { @MainActor in
			let handler = GenericCoTHandler.shared
			handler.accessoryManager = accessoryManagerRef

			if let cotMessage = handler.handleIncomingForwarderPacket(packetCopy) {
				await TAKServerManager.shared.broadcast(cotMessage)
				Logger.tak.info("Forwarded V1 generic CoT to TAK clients: \(cotMessage.type)")
			}
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

		let fromNode = packet.from
		// Hop off the main actor for everything CPU- or filesystem-heavy:
		// zstd decompression, CoT XML rebuilding, regex cleanup, KML/zip
		// generation, and `Data.write(to:)` into `Documents/TAK Routes/`.
		// Receiving a large route or shape used to freeze the UI for hundreds
		// of milliseconds — Copilot flagged this as a UI hang risk, and the
		// AccessoryManager dispatch loop also stalls because every other
		// portnum handler is `await`ing the same actor.
		//
		// `Task.detached` so we don't inherit `@MainActor` from the enclosing
		// `AccessoryManager` actor context. We hop back only for the
		// `LocalNotificationManager` work, which schedules `UNUserNotification`
		// requests and must be main-actor isolated.
		Task.detached(priority: .utility) {
			do {
				let compressor = MeshtasticTAK.TakCompressor()
				let takPacketV2 = try compressor.decompress(wirePayload)

				Logger.tak.info("Decompressed ATAK V2 packet from node \(fromNode): \(takPacketV2.callsign)")

				// Convert TAKPacketV2 → CoT XML via SDK builder, then forward
				// the raw XML directly to TAK clients. Do NOT re-parse through
				// CoTMessage — that strips shape detail elements (link-point
				// vertices, strokeColor, fillColor, etc.) that ATAK needs.
				let builder = MeshtasticTAK.CotXmlBuilder()
				let rawCotXml = builder.build(takPacketV2)
				// Strip the XML declaration and collapse formatting whitespace —
				// TAK clients' TCP streaming parsers expect bare <event>...</event>
				// on a single line, not a formatted XML document with <?xml ...?>
				// prologue.
				//
				// The prologue match uses a permissive regex (`^\s*<\?xml[^>]*\?>`)
				// so it's stripped even if the SDK builder ever emits it with
				// single quotes, a different attribute order, or `standalone="yes"`
				// — a literal substring match would silently leak the declaration
				// mid-stream and tear down the TAK TCP connection.
				//
				// The inter-tag collapse only targets whitespace that sits between
				// `>` and `<` so we don't mangle multi-line text content (e.g. a
				// `<remarks>` chat body with embedded newlines).
				let cotXml = rawCotXml
					.replacingOccurrences(of: #"^\s*<\?xml[^>]*\?>"#, with: "", options: .regularExpression)
					.replacingOccurrences(of: #">\s+<"#, with: "><", options: .regularExpression)
					.trimmingCharacters(in: .whitespacesAndNewlines)

				// Logger.tak.debug("=== Received CoT XML (mesh, \(cotXml.count) chars) ===")
				// Logger.tak.debug("\(cotXml)")
				// Logger.tak.debug("=== End Raw XML ===")

				await TAKServerManager.shared.broadcastRawXml(cotXml)
				Logger.tak.info("Forwarded ATAK V2 to TAK clients (raw XML)")

				// Routes: iTAK ignores b-m-r from TCP streaming. Save as KML
				// data package to Documents/TAK Routes/ for manual import.
				// Both quote styles must be supported — the SDK builder emits
				// doubles but the regex-cleaned XML or a third-party emitter
				// could yield singles, and skipping the KML write would let
				// the route silently vanish.
				let isRouteType = cotXml.contains("type=\"b-m-r\"") || cotXml.contains("type='b-m-r'")
				if isRouteType {
					if let (fileName, zipData) = RouteDataPackageGenerator.generateDataPackage(routeXml: cotXml),
					   let savedURL = RouteDataPackageGenerator.saveToDocuments(fileName: fileName, zipData: zipData) {
						Logger.tak.info("Route data package saved: \(savedURL.path)")
						let routeName = RouteDataPackageGenerator.extractRouteName(routeXml: cotXml) ?? "Unknown Route"
						await MainActor.run {
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
		// `hop_limit=0` (the protobuf default) makes the firmware treat the
		// packet as already-exhausted and silently drop it before TX — the
		// "Sent TAK V2 packet to mesh" log fires, queueStatus comes back
		// clean, but peers never hear it on the air. Use the LoRa-config
		// hop_limit (configurable per radio) with a 3-hop fallback when the
		// config hasn't been received yet or is left at the protobuf default.
		meshPacket.hopLimit = takBroadcastHopLimit(forDevice: deviceNum)
		meshPacket.wantAck = true

		var toRadio = ToRadio()
		toRadio.packet = meshPacket

		try await send(toRadio, debugDescription: "Sending TAKPacket V2 to mesh")
		Logger.tak.info("Sent TAK V2 packet to mesh (port=78, channel=\(channel), size=\(wirePayload.count) bytes, hopLimit=\(meshPacket.hopLimit))")
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
		// stale for routes; ATAK uses 24h. We bump short stales up to
		// `minimumMeshStaleTTL` (15 minutes) so the object survives multi-hop
		// mesh delivery and renders on the receiving end.
		let freshXml = Self.ensureMinimumStaleForMesh(cotXml)
		let strippedXml = Self.stripNonEssentialElements(freshXml)
		let parser = MeshtasticTAK.CotXmlParser()
		let packet = try parser.parse(strippedXml)
		let compressor = MeshtasticTAK.TakCompressor()
		// compressWithRemarksFallback preserves <remarks> text when the
		// compressed packet fits under the LoRa MTU, and strips remarks
		// automatically if needed to fit. Returns nil if even without
		// remarks the packet exceeds the limit.
		let maxWirePayloadBytes = 225
		guard let wirePayload = try compressor.compressWithRemarksFallback(packet, maxWireBytes: maxWirePayloadBytes) else {
			// Compressor refused even after stripping <remarks> — payload is
			// genuinely too large for the LoRa MTU. Throw so the caller can
			// log it consistently with other send-path failures rather than
			// silently swallowing the drop (the `do/catch` in
			// `TAKMeshtasticBridge.sendToMesh` would otherwise treat this as
			// a successful send).
			Logger.tak.warning("Dropping oversized TAK packet: max=\(maxWirePayloadBytes)B xml=\(min(cotXml.count, 1024)) chars: \(String(cotXml.prefix(1024)))")
			throw AccessoryError.ioFailed("TAK V2 payload exceeds LoRa wire size limit (\(maxWirePayloadBytes) bytes) even with remarks stripped")
		}
		Logger.tak.info("TAK → mesh: xml=\(cotXml.count)B → stripped=\(strippedXml.count)B → compressed=\(wirePayload.count)B")

		try await sendTAKV2Packet(wirePayload, channel: channel)
	}

	// MARK: - Send Legacy TAK Packet to Mesh (Port 72, V1)

	/// Send a legacy V1 `TAKPacket` (bare protobuf, no zstd) to the mesh.
	/// Used for firmware <= 2.7.x that doesn't support the V2 wire format on
	/// port 78. The V1 schema supports only PLI and GeoChat — callers must
	/// drop any other CoT type before reaching this method.
	func sendTAKPacket(_ takPacket: MeshtasticProtobufs.TAKPacket, channel: UInt32 = 0) async throws {
		guard let activeConnection else {
			throw AccessoryError.connectionFailed("Not connected to Meshtastic device")
		}
		guard let deviceNum = activeConnection.device.num else {
			throw AccessoryError.connectionFailed("No device number available")
		}

		let payload: Data
		do {
			payload = try takPacket.serializedData()
		} catch {
			Logger.tak.error("Failed to serialize V1 TAKPacket: \(error.localizedDescription)")
			throw error
		}

		var dataMessage = DataMessage()
		dataMessage.portnum = .atakPlugin  // Port 72 (legacy V1)
		dataMessage.payload = payload

		var meshPacket = MeshPacket()
		meshPacket.to = 0xFFFFFFFF  // Broadcast
		meshPacket.from = UInt32(deviceNum)
		meshPacket.channel = channel
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.decoded = dataMessage
		// Same hop_limit / want_ack fix as the V2 path: a `hop_limit=0`
		// MeshPacket is treated as already-exhausted by the radio firmware
		// and never gets transmitted on the LoRa channel.
		meshPacket.hopLimit = takBroadcastHopLimit(forDevice: deviceNum)
		meshPacket.wantAck = true

		var toRadio = ToRadio()
		toRadio.packet = meshPacket

		try await send(toRadio, debugDescription: "Sending legacy V1 TAKPacket to mesh")
		Logger.tak.info("Sent V1 TAK packet to mesh (port=72, channel=\(channel), size=\(payload.count) bytes, hopLimit=\(meshPacket.hopLimit))")
	}

	/// Resolve the hop-limit to stamp on broadcast TAK MeshPackets. Reads
	/// the connected node's persisted `LoRaConfig.hopLimit` (set by the
	/// firmware-side configuration the user picked in **Settings → LoRa**)
	/// and falls back to 3 hops when it's unavailable or left at the
	/// protobuf default of 0 — sending with `hop_limit=0` causes the
	/// firmware to treat the packet as already-exhausted and drop it
	/// before transmit, which is the same trap Android-side
	/// TAKMeshIntegration used to hit before it standardised on 3.
	func takBroadcastHopLimit(forDevice deviceNum: Int64) -> UInt32 {
		let fallback: UInt32 = 3
		guard let node = getNodeInfo(id: deviceNum, context: context) else { return fallback }
		let configured = node.loRaConfig?.hopLimit ?? 0
		return configured > 0 ? UInt32(truncatingIfNeeded: configured) : fallback
	}

	/// Ensure static CoT types (routes, shapes, markers) have at least 15 minutes
	/// of stale time remaining. iTAK uses 2-min stale for routes while ATAK uses
	/// 24h. Over LoRa mesh with multi-hop relay, a short stale means the object
	/// arrives already expired and ATAK silently discards it. PLI and GeoChat are
	/// left untouched — their stale times are semantically meaningful. Update
	/// both the docstring and the constant together so the assumed TTL stays
	/// canonical.
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
		// Both regexes accept either single- or double-quoted attribute
		// values — `CoTMessage.toXML()` emits singles, the SDK builder emits
		// doubles, and third-party generators are free to do either. Anchoring
		// on one quote style silently skipped half the static CoT we wanted to
		// extend, which let routes / shapes / markers arrive already-expired
		// after mesh forwarding (the exact failure this helper exists to fix).
		// Quick check: does the type match a static prefix?
		guard let typeRe = try? NSRegularExpression(pattern: #"<event\s[^>]*\btype\s*=\s*(['"])([^'"]*)\1"#),
			  let typeMatch = typeRe.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
			  let typeRange = Range(typeMatch.range(at: 2), in: xml) else { return xml }
		let type = String(xml[typeRange])
		guard staticCoTTypePrefixes.contains(where: { type.hasPrefix($0) }) else { return xml }

		// Extract current stale timestamp
		guard let staleRe = try? NSRegularExpression(pattern: #"\bstale\s*=\s*(['"])([^'"]*)\1"#),
			  let staleMatch = staleRe.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
			  let staleQuoteRange = Range(staleMatch.range(at: 1), in: xml),
			  let staleValueRange = Range(staleMatch.range(at: 2), in: xml),
			  let staleFullRange = Range(staleMatch.range, in: xml) else { return xml }
		let staleStr = String(xml[staleValueRange])
		guard let staleDate = isoFormatter.date(from: staleStr) ?? isoFormatterFrac.date(from: staleStr) else { return xml }

		let now = Date()
		let remaining = staleDate.timeIntervalSince(now)
		guard remaining < minimumMeshStaleTTL else { return xml }

		// Extend to now + minimumMeshStaleTTL, preserving the original
		// quote style so we don't replace `stale='...'` with `stale="..."`
		// inside an otherwise single-quoted CoTMessage emission.
		let newStale = now.addingTimeInterval(minimumMeshStaleTTL)
		let newStaleStr = isoFormatter.string(from: newStale)
		let quote = String(xml[staleQuoteRange])
		var result = xml
		result.replaceSubrange(staleFullRange, with: "stale=\(quote)\(newStaleStr)\(quote)")
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
