//
//  RoutingError.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/4/22.
//
import Foundation
import SwiftUI
import MeshtasticProtobufs

enum RoutingError: Int, CaseIterable, Identifiable {

	case none = 0
	case noRoute = 1
	case gotNak = 2
	case timeout = 3
	case noInterface = 4
	case maxRetransmit = 5
	case noChannel = 6
	case tooLarge = 7
	case noResponse = 8
	case dutyCycleLimit = 9
	case badRequest = 32
	case notAuthorized = 33
	case pkiFailed = 34
	case pkiUnknownPubkey = 35
	case adminBadSessionKey = 36
	case adminPublicKeyUnauthorized = 37
	case rateLimitExceeded = 38
	case pkiSendFailPublicKey = 39

	var id: Int { self.rawValue }
	var display: String {
		switch self {

		case .none:
			return String(localized: "Delivered to recipient", comment: "RoutingError.display")
		case .noRoute:
			return String(localized: "Failed to deliver to mesh", comment: "RoutingError.display")
		case .gotNak:
			return String(localized: "Failed to deliver to mesh", comment: "RoutingError.display")
		case .timeout:
			return String(localized: "Failed to deliver to mesh", comment: "RoutingError.display")
		case .noInterface:
			return String(localized: "No radio interface", comment: "RoutingError.display")
		case .maxRetransmit:
			return String(localized: "Failed to deliver to mesh", comment: "RoutingError.display")
		case .noChannel:
			return String(localized: "Channel/key mismatch", comment: "RoutingError.display")
		case .tooLarge:
			return String(localized: "Message is too large to send", comment: "RoutingError.display")
		case .noResponse:
			return String(localized: "No app response", comment: "RoutingError.display")
		case .dutyCycleLimit:
			return String(localized: "Duty cycle limit", comment: "RoutingError.display")
		case .badRequest:
			return String(localized: "Invalid request", comment: "RoutingError.display")
		case .notAuthorized:
			return String(localized: "Not authorized", comment: "RoutingError.display")
		case .pkiFailed:
			return String(localized: "Could not send encrypted message", comment: "RoutingError.display")
		case .pkiUnknownPubkey:
			return String(localized: "Recipient needs your key", comment: "RoutingError.display")
		case .adminBadSessionKey:
			return String(localized: "Admin session expired", comment: "RoutingError.display")
		case .adminPublicKeyUnauthorized:
			return String(localized: "Admin key not authorized", comment: "RoutingError.display")
		case .rateLimitExceeded:
			return String(localized: "Rate limited", comment: "RoutingError.display")
		case .pkiSendFailPublicKey:
			return String(localized: "Recipient key unavailable", comment: "RoutingError.display")
		}
	}
	var description: String {
		switch self {
		case .none:
			return String(localized: "The recipient confirmed this message.", comment: "RoutingError.description")
		case .noRoute:
			return String(localized: "No route to the destination node was found in the mesh. Try again when more nodes are reachable.", comment: "RoutingError.description")
		case .gotNak:
			return String(localized: "A node rejected this message. Try again when the route changes.", comment: "RoutingError.description")
		case .timeout:
			return String(localized: "No acknowledgment was received in time. Try again when you have better signal or more mesh coverage.", comment: "RoutingError.description")
		case .noInterface:
			return String(localized: "The sender has no usable radio interface for this message.", comment: "RoutingError.description")
		case .maxRetransmit:
			return String(localized: "No node confirmed this message. Try again when you have better signal or more mesh coverage.", comment: "RoutingError.description")
		case .noChannel:
			return String(localized: "The sender or recipient could not use a matching channel/key for this message.", comment: "RoutingError.description")
		case .tooLarge:
			return String(localized: "Shorten the message and send it again.", comment: "RoutingError.description")
		case .noResponse:
			return String(localized: "The destination received the request, but no app or module responded. Try again when the recipient is reachable.", comment: "RoutingError.description")
		case .dutyCycleLimit:
			return String(localized: "Local airtime limits are temporarily blocking sends. Wait before trying again.", comment: "RoutingError.description")
		case .badRequest:
			return String(localized: "The destination rejected this request as invalid.", comment: "RoutingError.description")
		case .notAuthorized:
			return String(localized: "The destination refused this request because it is not authorized.", comment: "RoutingError.description")
		case .pkiFailed:
			return String(localized: "The encrypted send path could not be used. Wait for node info or keys to sync, then try again.", comment: "RoutingError.description")
		case .pkiUnknownPubkey:
			return String(localized: "The recipient does not know your public key yet. Your node may share its info automatically; try again after it syncs.", comment: "RoutingError.description")
		case .adminBadSessionKey:
			return String(localized: "The admin session key is missing, expired, or invalid. Request a new session before trying again.", comment: "RoutingError.description")
		case .adminPublicKeyUnauthorized:
			return String(localized: "The remote node does not authorize your admin key.", comment: "RoutingError.description")
		case .rateLimitExceeded:
			return String(localized: "Messages are being sent too quickly. Wait before trying again.", comment: "RoutingError.description")
		case .pkiSendFailPublicKey:
			return String(localized: "Your node does not have the recipient's public key yet. Wait for node info to sync, then try again.", comment: "RoutingError.description")
		}
	}
	var color: Color {
		if self == .none {
			return Color(uiColor: .secondaryLabel)
		} else if self.canRetry {
			return Color(uiColor: .systemOrange)
		} else {
			return Color(uiColor: .systemRed)
		}
	}
	var canRetry: Bool {
		switch self {
		case .none:
			return false
		case .noRoute:
			return true
		case .gotNak:
			return true
		case .timeout:
			return true
		case .noInterface:
			return true
		case .maxRetransmit:
			return true
		case .noChannel:
			return false
		case .tooLarge:
			return false
		case .noResponse:
			return true
		case .dutyCycleLimit:
			return true
		case .badRequest:
			return false
		case .notAuthorized:
			return false
		case .pkiFailed:
			return true
		case .pkiUnknownPubkey:
			return true
		case .adminBadSessionKey:
			return true
		case .adminPublicKeyUnauthorized:
			return false
		case .rateLimitExceeded:
			return true
		case .pkiSendFailPublicKey:
			return true
		}
	}
	func protoEnumValue() -> Routing.Error {

		switch self {

		case .none:
			return Routing.Error.none
		case .noRoute:
			return Routing.Error.noRoute
		case .gotNak:
			return Routing.Error.gotNak
		case .timeout:
			return Routing.Error.timeout
		case .noInterface:
			return Routing.Error.noInterface
		case .maxRetransmit:
			return Routing.Error.maxRetransmit
		case .noChannel:
			return Routing.Error.noChannel
		case .tooLarge:
			return Routing.Error.tooLarge
		case .noResponse:
			return Routing.Error.noResponse
		case .dutyCycleLimit:
			return Routing.Error.dutyCycleLimit
		case .badRequest:
			return Routing.Error.badRequest
		case .notAuthorized:
			return Routing.Error.notAuthorized
		case .pkiFailed:
			return Routing.Error.pkiFailed
		case .pkiUnknownPubkey:
			return Routing.Error.pkiUnknownPubkey
		case .adminBadSessionKey:
			return Routing.Error.adminBadSessionKey
		case .adminPublicKeyUnauthorized:
			return Routing.Error.adminPublicKeyUnauthorized
		case .rateLimitExceeded:
			return Routing.Error.rateLimitExceeded
		case .pkiSendFailPublicKey:
			return Routing.Error.pkiSendFailPublicKey
		}
	}
}
