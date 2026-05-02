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

	var id: Int { self.rawValue }
	var display: String {
		switch self {

		case .none:
			return "Acknowledged".localized
		case .noRoute:
			return "No Route".localized
		case .gotNak:
			return "Received a negative acknowledgment".localized
		case .timeout:
			return "Timeout".localized
		case .noInterface:
			return "No Interface".localized
		case .maxRetransmit:
			return "Max Retransmission Reached".localized
		case .noChannel:
			return "No Channel".localized
		case .tooLarge:
			return "The packet is too large".localized
		case .noResponse:
			return "No Response".localized
		case .dutyCycleLimit:
			return "Regional Duty Cycle Limit Reached".localized
		case .badRequest:
			return "Bad Request".localized
		case .notAuthorized:
			return "Not Authorized".localized
		case .pkiFailed:
			return "Encrypted Send Failed".localized
		case .pkiUnknownPubkey:
			return "Unknown public key".localized
		case .adminBadSessionKey:
			return "Bad admin session key".localized
		case .adminPublicKeyUnauthorized:
			return "Unauthorized admin public key".localized
		case .rateLimitExceeded:
			return "Rate Limit Exceeded".localized
		}
	}
	var description: String {
		switch self {
		case .none:
			return "Message was successfully delivered to the recipient.".localized
		case .noRoute:
			return "No route to the destination node was found in the mesh.".localized
		case .gotNak:
			return "A node in the path explicitly rejected the packet.".localized
		case .timeout:
			return "No acknowledgment was received within the expected time window.".localized
		case .noInterface:
			return "The radio interface needed to send the packet is unavailable.".localized
		case .maxRetransmit:
			return "The packet was retransmitted the maximum number of times without acknowledgment.".localized
		case .noChannel:
			return "The channel required for this message is not configured on the device.".localized
		case .tooLarge:
			return "The message exceeds the maximum packet size and cannot be sent.".localized
		case .noResponse:
			return "The destination node did not respond to the request.".localized
		case .dutyCycleLimit:
			return "The regional duty cycle limit has been reached; transmissions are temporarily paused.".localized
		case .badRequest:
			return "The request was malformed or contained invalid parameters.".localized
		case .notAuthorized:
			return "The requesting node is not authorized to perform this action.".localized
		case .pkiFailed:
			return "Public key encryption failed; the message could not be encrypted for the recipient.".localized
		case .pkiUnknownPubkey:
			return "The recipient's public key is not known; direct message encryption is not possible.".localized
		case .adminBadSessionKey:
			return "The admin session key is invalid or has expired.".localized
		case .adminPublicKeyUnauthorized:
			return "The admin public key is not in the authorized list on the remote node.".localized
		case .rateLimitExceeded:
			return "Too many requests were sent in a short period; wait before retrying.".localized
		}
	}
	var color: Color {
		if self == .none {
			return Color.secondary
		} else if self.canRetry {
			return Color.orange
		} else {
			return Color.red
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
			return true
		case .tooLarge:
			return false
		case .noResponse:
			return true
		case .dutyCycleLimit:
			return true
		case .badRequest:
			return true
		case .notAuthorized:
			return true
		case .pkiFailed:
			return true
		case .pkiUnknownPubkey:
			return true
		case .adminBadSessionKey:
			return true
		case .adminPublicKeyUnauthorized:
			return true
		case .rateLimitExceeded:
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
		}
	}
}
