//
//  RoutingError.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/4/22.
//
import Foundation
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

	var id: Int { self.rawValue }
	var display: String {
		switch self {

		case .none:
			return NSLocalizedString("routing.acknowledged", comment: "No comment provided")
		case .noRoute:
			return NSLocalizedString("routing.noroute", comment: "No comment provided")
		case .gotNak:
			return NSLocalizedString("routing.gotnak", comment: "No comment provided")
		case .timeout:
			return NSLocalizedString("routing.timeout", comment: "No comment provided")
		case .noInterface:
			return NSLocalizedString("routing.nointerface", comment: "No comment provided")
		case .maxRetransmit:
			return NSLocalizedString("routing.maxretransmit", comment: "No comment provided")
		case .noChannel:
			return NSLocalizedString("routing.nochannel", comment: "No comment provided")
		case .tooLarge:
			return NSLocalizedString("routing.toolarge", comment: "No comment provided")
		case .noResponse:
			return NSLocalizedString("routing.noresponse", comment: "No comment provided")
		case .dutyCycleLimit:
			return NSLocalizedString("routing.dutycyclelimit", comment: "No comment provided")
		case .badRequest:
			return NSLocalizedString("routing.badRequest", comment: "No comment provided")
		case .notAuthorized:
			return NSLocalizedString("routing.notauthorized", comment: "No comment provided")
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
