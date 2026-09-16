//
//  MeshContactURL.swift
//  Meshtastic
//

import Foundation
import MeshtasticProtobufs

struct MeshContactURL: Sendable {

	static let host = MeshtasticChannelURL.host
	static let appScheme = MeshtasticChannelURL.appScheme
	static let contactPathSegment = "v"
	static let canonicalPrefix = "https://meshtastic.org/v/"
	static let maximumPayloadCharacters = 16 * 1_024

	let payload: String
	let contact: SharedContact
	let exchangeRequested: Bool

	enum ParseError: LocalizedError, Equatable {
		case empty
		case notContactURL
		case missingPayload
		case payloadTooLarge
		case invalidBase64
		case invalidContact

		var errorDescription: String? {
			switch self {
			case .empty:
				return "Contact link is empty."
			case .notContactURL:
				return "This is not a Meshtastic contact link."
			case .missingPayload:
				return "Contact link is missing contact data."
			case .payloadTooLarge:
				return "Contact link is too large."
			case .invalidBase64, .invalidContact:
				return "Contact data could not be decoded."
			}
		}
	}

	static func parse(_ value: String) throws -> MeshContactURL {
		let trimmed = value
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))

		guard !trimmed.isEmpty else {
			throw ParseError.empty
		}
		guard let url = URL(string: trimmed), isContactURL(url) else {
			throw ParseError.notContactURL
		}
		guard let payload = url.fragment, !payload.isEmpty else {
			throw ParseError.missingPayload
		}
		guard payload.count <= maximumPayloadCharacters else {
			throw ParseError.payloadTooLarge
		}
		guard let data = Data(base64Encoded: paddedBase64(payload)) else {
			throw ParseError.invalidBase64
		}
		guard let contact = try? SharedContact(serializedBytes: data),
			  contact.nodeNum > 0,
			  !contact.user.id.isEmpty else {
			throw ParseError.invalidContact
		}

		let exchangeValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
			.queryItems?
			.first { $0.name.caseInsensitiveCompare("exchange") == .orderedSame }?
			.value?
			.lowercased()
		let exchangeRequested = exchangeValue.map { ["1", "true", "yes"].contains($0) } ?? false

		return MeshContactURL(
			payload: payload,
			contact: contact,
			exchangeRequested: exchangeRequested
		)
	}

	static func urlString(for contact: SharedContact, exchangeRequested: Bool = false) throws -> String {
		let payload = try payloadString(for: contact)
		let query = exchangeRequested ? "?exchange=true" : ""
		return "\(canonicalPrefix)\(query)#\(payload)"
	}

	static func payloadString(for contact: SharedContact) throws -> String {
		urlSafeBase64(try contact.serializedData().base64EncodedString())
	}

	static func canHandle(_ url: URL) -> Bool {
		isContactURL(url) && !(url.fragment?.isEmpty ?? true)
	}

	static func withoutExchangeRequest(_ url: URL) -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return url
		}
		components.queryItems = components.queryItems?.filter {
			$0.name.caseInsensitiveCompare("exchange") != .orderedSame
		}
		if components.queryItems?.isEmpty == true {
			components.queryItems = nil
		}
		return components.url ?? url
	}

	private static func isContactURL(_ url: URL) -> Bool {
		let pathSegments = url.pathComponents
			.filter { $0 != "/" }
			.map { $0.lowercased() }
		guard url.user == nil, url.password == nil, url.port == nil else {
			return false
		}

		if url.scheme?.lowercased() == appScheme {
			if url.host == nil {
				return pathSegments == [contactPathSegment]
			}
			return url.host?.lowercased() == contactPathSegment && pathSegments.isEmpty
		}

		guard url.scheme?.lowercased() == "https",
			  let urlHost = url.host?.lowercased(),
			  urlHost == host || urlHost == "www.\(host)" else {
			return false
		}
		return pathSegments == [contactPathSegment]
	}

	private static func urlSafeBase64(_ value: String) -> String {
		value
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}

	private static func paddedBase64(_ value: String) -> String {
		var result = value
			.replacingOccurrences(of: "-", with: "+")
			.replacingOccurrences(of: "_", with: "/")
		if result.count % 4 != 0 {
			result.append(String(repeating: "=", count: 4 - result.count % 4))
		}
		return result
	}
}
