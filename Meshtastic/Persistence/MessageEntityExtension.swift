//
//  MessageEntityExtension.swift
//  Meshtastic
//
//  Created by Ben on 8/22/23.
//

import Foundation

import CoreData
import CoreLocation
import MapKit
import SwiftUI

extension MessageEntity {
	var timestamp: Date {
		let time = messageTimestamp <= 0 ? receivedTimestamp : messageTimestamp
		return Date(timeIntervalSince1970: TimeInterval(time))
	}
}
