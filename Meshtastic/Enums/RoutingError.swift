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
			return "No route to recipient".localized
		case .gotNak:
			return "Message was rejected".localized
		case .timeout:
			return "Timed out".localized
		case .noInterface:
			return "Radio interface unavailable".localized
		case .maxRetransmit:
			return "Failed to deliver to mesh".localized
		case .noChannel:
			return "Channel/key mismatch".localized
		case .tooLarge:
			return "Message is too large to send".localized
		case .noResponse:
			return "No response from recipient".localized
		case .dutyCycleLimit:
			return "Duty cycle limit reached".localized
		case .badRequest:
			return "Message request invalid".localized
		case .notAuthorized:
			return "Not authorized to send".localized
		case .pkiFailed:
			return "Could not send encrypted message".localized
		case .pkiUnknownPubkey:
			return "Recipient needs your key".localized
		case .adminBadSessionKey:
			return "Admin session expired".localized
		case .adminPublicKeyUnauthorized:
			return "Admin key not authorized".localized
		case .rateLimitExceeded:
			return "Sending too quickly".localized
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
			return "A node in the path rejected this message. Try again when the route changes.".localized
		case .timeout:
			return "No acknowledgment was received in time. Try again when you have better signal or more mesh coverage.".localized
		case .noInterface:
			return "The radio interface needed to send this message is unavailable.".localized
		case .maxRetransmit:
			return "No node confirmed this message. Try again when you have better signal or more mesh coverage.".localized
		case .noChannel:
			return "Check the channel and key settings before sending again.".localized
		case .tooLarge:
			return "Shorten the message and send it again.".localized
		case .noResponse:
			return "The recipient did not respond. Try again when the recipient is reachable.".localized
		case .dutyCycleLimit:
			return "Your region's duty cycle limit has been reached. Wait before sending again.".localized
		case .badRequest:
			return "The radio could not send this message because the request was invalid.".localized
		case .notAuthorized:
			return "Your node is not authorized to send this message in the current context.".localized
		case .pkiFailed:
			return "Encryption failed. Wait for node info or keys to sync, then try again.".localized
		case .pkiUnknownPubkey:
			return "The recipient does not know your public key yet. Your node may share its info automatically; try again after it syncs.".localized
		case .adminBadSessionKey:
			return "The admin session key is invalid or expired. Request a new session before trying again.".localized
		case .adminPublicKeyUnauthorized:
			return "The remote node does not authorize your admin public key.".localized
		case .rateLimitExceeded:
			return "Too many messages were sent in a short period. Wait before trying again.".localized
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
