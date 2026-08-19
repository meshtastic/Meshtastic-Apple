//
//  EventEdition.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 8/16/26.
//
//  Display details for a radio running event firmware. Shimmed locally rather than
//  reusing the iOS `FirmwareEditions` enum, which pulls in String+localized and the
//  UIKit-flavored extensions the TV target deliberately stays clear of. Names are
//  kept in sync with Meshtastic/Enums/FirmwareEditionEnum.swift.
//

import Foundation
import MeshtasticProtobufs

/// A non-vanilla firmware edition, resolved to what the stats strip needs.
struct EventEdition: Equatable {
	let name: String
	/// Edition artwork in the TV asset catalog, or nil to fall back to the
	/// Meshtastic mark — the mark is never replaced, only supplemented.
	let assetName: String?

	/// Nil for stock firmware, which shows no badge at all.
	init?(_ edition: FirmwareEdition) {
		switch edition {
		case .vanilla, .UNRECOGNIZED:
			return nil
		case .smartCitizen:
			self.init(name: "Smart Citizen", assetName: nil)
		case .openSauce:
			self.init(name: "Open Sauce", assetName: nil)
		case .defcon:
			self.init(name: "DEFCON", assetName: "EventFirmwareDEFCON")
		case .burningMan:
			self.init(name: "Burning Man", assetName: nil)
		case .hamvention:
			self.init(name: "Hamvention", assetName: "EventFirmwareHAMVENTION")
		case .fab:
			self.init(name: "FAB", assetName: "EventFirmwareFAB")
		case .diyEdition:
			self.init(name: "DIY Edition", assetName: nil)
		}
	}

	private init(name: String, assetName: String?) {
		self.name = name
		self.assetName = assetName
	}
}
