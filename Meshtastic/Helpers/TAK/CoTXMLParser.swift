//
//  CoTXMLParser.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import OSLog

/// XML Parser delegate for parsing incoming CoT (Cursor on Target) messages from TAK clients
final class CoTXMLParser: NSObject, XMLParserDelegate {
	private let data: Data
	private var cotMessage: CoTMessage?
	private var parseError: Error?

	// Current parsing state
	private var currentElement = ""
	private var currentText = ""

	// Temporary attribute storage during parsing
	private var eventAttributes: [String: String] = [:]
	private var pointAttributes: [String: String] = [:]
	private var contactAttributes: [String: String] = [:]
	private var groupAttributes: [String: String] = [:]
	private var statusAttributes: [String: String] = [:]
	private var trackAttributes: [String: String] = [:]
	private var chatAttributes: [String: String] = [:]
	private var chatgrpAttributes: [String: String] = [:]
	private var remarksAttributes: [String: String] = [:]
	private var remarksText = ""
	private var linkAttributes: [String: String] = [:]

	// Track element hierarchy for nested elements
	private var elementStack: [String] = []

	// Raw detail XML for unrecognized elements (markers, shapes, colors, etc.)
	private var rawDetailXML = ""
	private var isCapturingRawDetail = false
	private var rawDetailDepth = 0

	// Known detail elements we handle explicitly
	private let knownDetailElements: Set<String> = [
		"contact", "__group", "status", "track", "__chat", "chatgrp",
		"remarks", "link", "uid", "__serverdestination"
	]

	init(data: Data) {
		self.data = data
	}

	/// Parse the XML data and return a CoTMessage
	func parse() throws -> CoTMessage {
		let parser = XMLParser(data: data)
		parser.delegate = self
		parser.shouldProcessNamespaces = false
		parser.shouldReportNamespacePrefixes = false

		guard parser.parse() else {
			if let error = parseError {
				throw error
			}
			throw CoTParseError.parseFailed(parser.parserError?.localizedDescription ?? "Unknown error")
		}

		guard let message = cotMessage else {
			throw CoTParseError.invalidMessage
		}

		return message
	}

	// MARK: - XMLParserDelegate

	func parser(_ parser: XMLParser, didStartElement elementName: String,
				namespaceURI: String?, qualifiedName qName: String?,
				attributes attributeDict: [String: String] = [:]) {
		elementStack.append(elementName)
		currentElement = elementName
		currentText = ""

		// Check if we're inside <detail> and this is an unrecognized element
		let isInsideDetail = elementStack.contains("detail") && elementName != "detail"

		if isCapturingRawDetail {
			// Continue capturing nested elements
			rawDetailDepth += 1
			rawDetailXML += buildOpeningTag(elementName, attributes: attributeDict)
		} else if isInsideDetail && !knownDetailElements.contains(elementName) {
			// Start capturing this unrecognized element
			isCapturingRawDetail = true
			rawDetailDepth = 1
			rawDetailXML += buildOpeningTag(elementName, attributes: attributeDict)
		}

		switch elementName {
		case "event":
			eventAttributes = attributeDict
		case "point":
			pointAttributes = attributeDict
		case "contact":
			contactAttributes = attributeDict
		case "__group":
			groupAttributes = attributeDict
		case "status":
			statusAttributes = attributeDict
		case "track":
			trackAttributes = attributeDict
		case "__chat":
			chatAttributes = attributeDict
		case "chatgrp":
			chatgrpAttributes = attributeDict
		case "remarks":
			remarksAttributes = attributeDict
		case "link":
			linkAttributes = attributeDict
		default:
			break
		}
	}

	/// Build an XML opening tag with attributes
	private func buildOpeningTag(_ elementName: String, attributes: [String: String]) -> String {
		var tag = "<\(elementName)"
		for (key, value) in attributes {
			tag += " \(key)='\(value.xmlEscaped)'"
		}
		tag += ">"
		return tag
	}

	func parser(_ parser: XMLParser, foundCharacters string: String) {
		currentText += string

		// Capture text content for raw detail elements
		if isCapturingRawDetail {
			rawDetailXML += string.xmlEscaped
		}
	}

	func parser(_ parser: XMLParser, didEndElement elementName: String,
				namespaceURI: String?, qualifiedName qName: String?) {
		if elementName == "remarks" {
			remarksText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		// Handle raw detail element closing
		if isCapturingRawDetail {
			rawDetailXML += "</\(elementName)>"
			rawDetailDepth -= 1
			if rawDetailDepth == 0 {
				isCapturingRawDetail = false
			}
		}

		if elementName == "event" {
			buildCoTMessage()
		}

		elementStack.removeLast()
		currentElement = elementStack.last ?? ""
	}

	func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
		self.parseError = parseError
		Logger.tak.error("CoT XML parse error: \(parseError.localizedDescription)")
	}

	// MARK: - Build CoTMessage

	private func buildCoTMessage() {
		Logger.tak.debug("=== Building CoTMessage from XML ===")
		Logger.tak.debug("Event attributes: \(self.eventAttributes)")
		Logger.tak.debug("Point attributes: \(self.pointAttributes)")
		Logger.tak.debug("Contact attributes: \(self.contactAttributes)")
		Logger.tak.debug("Group attributes: \(self.groupAttributes)")
		Logger.tak.debug("Status attributes: \(self.statusAttributes)")
		Logger.tak.debug("Track attributes: \(self.trackAttributes)")
		Logger.tak.debug("Chat attributes: \(self.chatAttributes)")
		Logger.tak.debug("Remarks text: \(self.remarksText)")

		// Parse timestamps
		let time = parseDate(eventAttributes["time"])
		let start = parseDate(eventAttributes["start"])
		let stale = parseDate(eventAttributes["stale"])

		// Build contact if present
		var contact: CoTContact?
		if !contactAttributes.isEmpty {
			contact = CoTContact(
				callsign: contactAttributes["callsign"] ?? "",
				endpoint: contactAttributes["endpoint"],
				phone: contactAttributes["phone"]
			)
			Logger.tak.debug("Parsed contact: callsign=\(contact?.callsign ?? "nil")")
		}

		// Build group if present
		var group: CoTGroup?
		if !groupAttributes.isEmpty {
			group = CoTGroup(
				name: groupAttributes["name"] ?? "Cyan",
				role: groupAttributes["role"] ?? "Team Member"
			)
			Logger.tak.debug("Parsed group: name=\(group?.name ?? "nil"), role=\(group?.role ?? "nil")")
		}

		// Build status if present
		var status: CoTStatus?
		if let batteryStr = statusAttributes["battery"], let battery = Int(batteryStr) {
			status = CoTStatus(battery: battery)
			Logger.tak.debug("Parsed status: battery=\(battery)")
		}

		// Build track if present
		var track: CoTTrack?
		if !trackAttributes.isEmpty {
			let speed = Double(trackAttributes["speed"] ?? "0") ?? 0
			let course = Double(trackAttributes["course"] ?? "0") ?? 0
			track = CoTTrack(speed: speed, course: course)
			Logger.tak.debug("Parsed track: speed=\(speed), course=\(course)")
		}

		// Build chat if present
		var chat: CoTChat?
		if !chatAttributes.isEmpty {
			chat = CoTChat(
				message: remarksText,
				senderCallsign: chatAttributes["senderCallsign"],
				chatroom: chatAttributes["chatroom"] ?? chatAttributes["id"] ?? "All Chat Rooms"
			)
			Logger.tak.debug("Parsed chat: message=\(self.remarksText.prefix(50)), chatroom=\(chat?.chatroom ?? "nil")")
		}

		let uid = eventAttributes["uid"] ?? UUID().uuidString
		let type = eventAttributes["type"] ?? "a-f-G-U-C"
		let latitude = Double(pointAttributes["lat"] ?? "0") ?? 0
		let longitude = Double(pointAttributes["lon"] ?? "0") ?? 0
		let hae = Double(pointAttributes["hae"] ?? "9999999") ?? 9999999

		Logger.tak.debug("Building CoTMessage: uid=\(uid), type=\(type)")
		Logger.tak.debug("  location: lat=\(latitude), lon=\(longitude), hae=\(hae)")

		cotMessage = CoTMessage(
			uid: uid,
			type: type,
			time: time,
			start: start,
			stale: stale,
			how: eventAttributes["how"] ?? "m-g",
			latitude: latitude,
			longitude: longitude,
			hae: hae,
			ce: Double(pointAttributes["ce"] ?? "9999999") ?? 9999999,
			le: Double(pointAttributes["le"] ?? "9999999") ?? 9999999,
			contact: contact,
			group: group,
			status: status,
			track: track,
			chat: chat,
			remarks: chat == nil && !remarksText.isEmpty ? remarksText : nil,
			rawDetailXML: rawDetailXML.isEmpty ? nil : rawDetailXML
		)

		if !rawDetailXML.isEmpty {
			Logger.tak.debug("Captured raw detail XML: \(self.rawDetailXML.prefix(200))...")
		}

		Logger.tak.debug("=== CoTMessage built successfully ===")
	}

	// MARK: - Date Parsing

	private func parseDate(_ string: String?) -> Date {
		guard let string else { return Date() }

		// Try ISO8601 with fractional seconds first
		let formatterWithFractional = ISO8601DateFormatter()
		formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = formatterWithFractional.date(from: string) {
			return date
		}

		// Try ISO8601 without fractional seconds
		let formatterWithoutFractional = ISO8601DateFormatter()
		formatterWithoutFractional.formatOptions = [.withInternetDateTime]
		if let date = formatterWithoutFractional.date(from: string) {
			return date
		}

		// Try basic date formatter
		let basicFormatter = DateFormatter()
		basicFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
		basicFormatter.timeZone = TimeZone(identifier: "UTC")
		if let date = basicFormatter.date(from: string) {
			return date
		}

		Logger.tak.warning("Failed to parse CoT date: \(string)")
		return Date()
	}
}

// MARK: - Parse Error

enum CoTParseError: LocalizedError {
	case parseFailed(String)
	case invalidMessage
	case emptyData

	var errorDescription: String? {
		switch self {
		case .parseFailed(let reason):
			return "Failed to parse CoT XML: \(reason)"
		case .invalidMessage:
			return "Invalid CoT message structure"
		case .emptyData:
			return "Empty data received"
		}
	}
}

// MARK: - CoTMessage Parsing Extension

extension CoTMessage {
	/// Parse CoT XML data into a CoTMessage (throwing version)
	static func parseData(_ data: Data) throws -> CoTMessage {
		guard !data.isEmpty else {
			throw CoTParseError.emptyData
		}

		let parser = CoTXMLParser(data: data)
		return try parser.parse()
	}
}
