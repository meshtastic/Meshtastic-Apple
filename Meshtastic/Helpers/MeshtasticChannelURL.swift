//
//  MeshtasticChannelURL.swift
//  Meshtastic
//
//  Centralized parsing and generation for Meshtastic channel URLs.
//

import Foundation
import MeshtasticProtobufs

// MARK: - MeshtasticChannelURL

struct MeshtasticChannelURL: Sendable {

	// MARK: - Constants

	static let host = "meshtastic.org"
	static let appScheme = "meshtastic"
	static let channelPathSegment = "e"
	static let canonicalPrefix = "https://meshtastic.org/e/"

	// MARK: - Properties

	let payload: String
	let channelSet: ChannelSet
	let addChannels: Bool

	// MARK: - Errors

	enum ParseError: LocalizedError, Equatable {
		case empty
		case notChannelURL
		case missingPayload
		case invalidBase64
		case invalidChannelSet

		var errorDescription: String? {
			switch self {
			case .empty:
				return "Channel link is empty."
			case .notChannelURL:
				return "This is not a Meshtastic channel link."
			case .missingPayload:
				return "Channel link is missing channel data."
			case .invalidBase64:
				return "Channel link contains invalid channel data."
			case .invalidChannelSet:
				return "Channel data could not be decoded."
			}
		}
	}

	// MARK: - Public API

	static func parse(_ value: String, defaultAddChannels: Bool = false) throws -> MeshtasticChannelURL {
		let trimmed = value
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))

		guard !trimmed.isEmpty else {
			throw ParseError.empty
		}

		let parsed = try parsePayloadAndMode(from: trimmed, defaultAddChannels: defaultAddChannels)
		var channelSet = try decodeChannelSet(payload: parsed.payload)

		if parsed.addChannels {
			channelSet.clearLoraConfig()
		}

		return MeshtasticChannelURL(payload: parsed.payload, channelSet: channelSet, addChannels: parsed.addChannels)
	}

	// MARK: - URL Helpers

	static func urlString(for channelSet: ChannelSet, addChannels: Bool = false) throws -> String {
		let encodedPayload = try payloadString(for: channelSet)
		let query = addChannels ? "?add=true" : ""
		return "\(canonicalPrefix)\(query)#\(encodedPayload)"
	}

	static func canHandle(_ url: URL) -> Bool {
		isChannelURL(url)
	}

	static func payloadString(for channelSet: ChannelSet) throws -> String {
		try channelSet.serializedData().base64EncodedString().base64ToBase64url()
	}

	// MARK: - Parsing Helpers

	private static func parsePayloadAndMode(from value: String, defaultAddChannels: Bool) throws -> (payload: String, addChannels: Bool) {
		guard let url = URL(string: value), url.scheme != nil || url.host != nil else {
			return (payload: value, addChannels: defaultAddChannels)
		}

		guard isChannelURL(url) else {
			throw ParseError.notChannelURL
		}

		let fragment = url.fragment ?? ""
		let fragmentParts = fragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
		let payload = String(fragmentParts.first ?? "")
		let fragmentQuery = fragmentParts.count > 1 ? String(fragmentParts[1]) : nil
		let addFromQuery = boolQueryValue(named: "add", in: url.query)
		let addFromFragment = boolQueryValue(named: "add", in: fragmentQuery)

		guard !payload.isEmpty else {
			throw ParseError.missingPayload
		}

		return (payload: payload, addChannels: addFromFragment ?? addFromQuery ?? defaultAddChannels)
	}

	private static func isChannelURL(_ url: URL) -> Bool {
		if url.scheme?.lowercased() == appScheme {
			let pathSegments = pathSegments(for: url)
			if url.host == nil {
				return pathSegments == [channelPathSegment]
			}
			return url.host?.lowercased() == channelPathSegment && pathSegments.isEmpty
		}

		let supportedHosts = [Self.host, "www.\(Self.host)"]
		guard let host = url.host?.lowercased(), supportedHosts.contains(host) else { return false }
		return pathSegments(for: url) == [channelPathSegment]
	}

	private static func pathSegments(for url: URL) -> [String] {
		url.pathComponents
			.filter { $0 != "/" }
			.map { $0.lowercased() }
	}

	private static func boolQueryValue(named name: String, in query: String?) -> Bool? {
		guard let query, !query.isEmpty else {
			return nil
		}

		for pair in query.split(separator: "&") {
			let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
			guard parts.first?.lowercased() == name.lowercased() else {
				continue
			}

			let rawValue = parts.count > 1 ? String(parts[1]) : "true"
			switch rawValue.removingPercentEncoding?.lowercased() ?? rawValue.lowercased() {
			case "1", "true", "yes":
				return true
			case "0", "false", "no":
				return false
			default:
				return nil
			}
		}

		return nil
	}

	// MARK: - Decoding Helpers

	private static func decodeChannelSet(payload: String) throws -> ChannelSet {
		let decodedString = payload.base64urlToBase64()
		guard let decodedData = Data(base64Encoded: decodedString) else {
			throw ParseError.invalidBase64
		}

		do {
			return try ChannelSet(serializedBytes: decodedData)
		} catch {
			throw ParseError.invalidChannelSet
		}
	}
}
