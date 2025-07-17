//
//  ChannelLock.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/22/25.
//
import SwiftUI

struct ChannelLock: View {

	@ObservedObject var channel: ChannelEntity
	var body: some View {
		/// Unencrypted - using no key at all or a known 1 byte key
		if channel.psk?.hexDescription.count ?? 0 < 3 {
			let preciseLoction = 17...32
			// Using precise location and have MQTT uplink enabled
			if channel.uplinkEnabled && preciseLoction ~= (Int(channel.positionPrecision)) {
				Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
					.foregroundColor(.red)
				// Using precise location
			} else if preciseLoction ~= (Int(channel.positionPrecision)) {
				Image(systemName: "lock.open.fill")
					.foregroundColor(.red)
				// Just unencrypted without any location or MQTT
			} else {
				Image(systemName: "lock.open.fill")
					.foregroundColor(.yellow)
			}
		} else {
			Image(systemName: "lock.fill")
				.foregroundColor(.green)
		}
	}
}
