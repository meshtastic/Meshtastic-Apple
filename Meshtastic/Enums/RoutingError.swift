//
//  RoutingError.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/4/22.
//
import Foundation

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

	var id: Int { self.rawValue }
	var display: String {
		get {
			switch self {

			case .none:
				return NSLocalizedString("routing.acknowledged", comment: "Acknowledged")
			case .noRoute:
				return NSLocalizedString("routing.noroute", comment: "No Route")
			case .gotNak:
				return NSLocalizedString("routing.gotnak", comment: "Received a negative acknowledgment")
			case .timeout:
				return NSLocalizedString("routing.timeout", comment: "Timeout")
			case .noInterface:
				return NSLocalizedString("routing.nointerface", comment: "No Interface")
			case .maxRetransmit:
				return NSLocalizedString("routing.maxretransmit", comment: "Max Retransmission Reached")
			case .noChannel:
				return NSLocalizedString("routing.nochannel", comment: "No Channel")
			case .tooLarge:
				return NSLocalizedString("routing.toolarge", comment: "The packet is too large")
			case .noResponse:
				return NSLocalizedString("routing.noresponse", comment: "No Response")
			case .dutyCycleLimit:
				return NSLocalizedString("routing.dutycyclelimit", comment: "Regional Duty Cycle Limit Reached")
			case .badRequest:
				return NSLocalizedString("routing.badRequest", comment: "Bad Request")
			case .notAuthorized:
				return NSLocalizedString("routing.notauthorized", comment: "Not Authorized")
			}
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

		}
	}
}
