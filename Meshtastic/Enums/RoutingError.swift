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
			return "Delivered to recipient".localized
		case .noRoute:
			return "Failed to deliver to mesh".localized
		case .gotNak:
			return "Failed to deliver to mesh".localized
		case .timeout:
			return "Failed to deliver to mesh".localized
		case .noInterface:
			return "No radio interface".localized
		case .maxRetransmit:
			return "Failed to deliver to mesh".localized
		case .noChannel:
			return "Channel/key mismatch".localized
		case .tooLarge:
			return "Message is too large to send".localized
		case .noResponse:
			return "No app response".localized
		case .dutyCycleLimit:
			return "Duty cycle limit".localized
		case .badRequest:
			return "Invalid request".localized
		case .notAuthorized:
			return "Not authorized".localized
		case .pkiFailed:
			return "Could not send encrypted message".localized
		case .pkiUnknownPubkey:
			return "Recipient needs your key".localized
		case .adminBadSessionKey:
			return "Admin session expired".localized
		case .adminPublicKeyUnauthorized:
			return "Admin key not authorized".localized
		case .rateLimitExceeded:
			return "Rate limited".localized
		case .pkiSendFailPublicKey:
			return "Recipient key unavailable".localized
		}
	}
	var description: String {
		switch self {
		case .none:
			return "The recipient confirmed this message.".localized
		case .noRoute:
			return "No route to the destination node was found in the mesh. Try again when more nodes are reachable.".localized
		case .gotNak:
			return "A node rejected this message. Try again when the route changes.".localized
		case .timeout:
			return "No acknowledgment was received in time. Try again when you have better signal or more mesh coverage.".localized
		case .noInterface:
			return "The sender has no usable radio interface for this message.".localized
		case .maxRetransmit:
			return "No node confirmed this message. Try again when you have better signal or more mesh coverage.".localized
		case .noChannel:
			return "The sender or recipient could not use a matching channel/key for this message.".localized
		case .tooLarge:
			return "Shorten the message and send it again.".localized
		case .noResponse:
			return "The destination received the request, but no app or module responded. Try again when the recipient is reachable.".localized
		case .dutyCycleLimit:
			return "Local airtime limits are temporarily blocking sends. Wait before trying again.".localized
		case .badRequest:
			return "The destination rejected this request as invalid.".localized
		case .notAuthorized:
			return "The destination refused this request because it is not authorized.".localized
		case .pkiFailed:
			return "The encrypted send path could not be used. Wait for node info or keys to sync, then try again.".localized
		case .pkiUnknownPubkey:
			return "The recipient does not know your public key yet. Your node may share its info automatically; try again after it syncs.".localized
		case .adminBadSessionKey:
			return "The admin session key is missing, expired, or invalid. Request a new session before trying again.".localized
		case .adminPublicKeyUnauthorized:
			return "The remote node does not authorize your admin key.".localized
		case .rateLimitExceeded:
			return "Messages are being sent too quickly. Wait before trying again.".localized
		case .pkiSendFailPublicKey:
			return "Your node does not have the recipient's public key yet. Wait for node info to sync, then try again.".localized
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
