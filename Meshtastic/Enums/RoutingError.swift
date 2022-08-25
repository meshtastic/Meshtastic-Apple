//
//  RoutingError.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/4/22.
//

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
	case badRequest = 32
	case notAuthorized = 33

	var id: Int { self.rawValue }
	var display: String {
		get {
			switch self {
			
			case .none:
				return "No Error."
			case .noRoute:
				return "No Route"
			case .gotNak:
				return "Received a nak"
			case .timeout:
				return "Timeout"
			case .noInterface:
				return "No Interface"
			case .maxRetransmit:
				return "Max Retransmission Reached"
			case .noChannel:
				return "No Channel"
			case .tooLarge:
				return "The packet is too large"
			case .noResponse:
				return "No Response"
			case .badRequest:
				return "Bad Request"
			case .notAuthorized:
				return "Not Authorized"
			}
		}
	}
	var description: String {
		get {
			switch self {
			
			case .none:
				return "This message is not a failure."
			case .noRoute:
				return "Our node doesn't have a route to the requested destination anymore."
			case .gotNak:
				return "We received a nak while trying to forward on your behalf."
			case .timeout:
				return "We timed out while attempting to route this packet."
			case .noInterface:
				return "No suitable interface could be found for delivering this packet."
			case .maxRetransmit:
				return "We reached the max retransmission count (Hop Limit) and have received no responses."
			case .noChannel:
				return "No suitable channel was found for sending this packet (i.e. was requested channel index disabled?)."
			case .tooLarge:
				return "The packet was too big for sending (exceeds interface MTU after encoding)."
			case .noResponse:
				return "The request had want_response set, the request reached the destination node, but no service on that node wants to send a response (possibly due to bad channel permissions)."
			case .badRequest:
				return "The application layer service on the remote node received your request, but considered your request somehow invalid."
			case .notAuthorized:
				return "The application layer service on the remote node received your request, but considered your request not authorized (i.e you did not send the request on the required bound channel)."
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
		case .badRequest:
			return Routing.Error.badRequest
		case .notAuthorized:
			return Routing.Error.notAuthorized
		}
	}
}
