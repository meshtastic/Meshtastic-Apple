//
//  AdminMessageList.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 7/2/22.
//
/*
Abstract:
A view showing the details for a node.
*/

import SwiftUI
import MapKit
import CoreLocation

struct AdminMessageList: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	var user: UserEntity?

	var body: some View {
		
		List {
			if user != nil {
			
				ForEach ( user!.adminMessageList ) { am in
				
					HStack {
						
						Text("\(am.adminDescription ?? NSLocalizedString("unknown", comment: "Unknown")) - \(Date(timeIntervalSince1970: TimeInterval(am.messageTimestamp)), style: .date) \(Date(timeIntervalSince1970: TimeInterval(am.messageTimestamp)).formattedDate(format: "h:mm:ss a"))")
							.font(.caption)
						
						if am.receivedACK {
							
							Image(systemName: "checkmark.square")
								.foregroundColor(.gray)
								.font(.caption)
							Text("routing.acknowledged").foregroundColor(.gray).font(.caption) + Text(": \(Date(timeIntervalSince1970: TimeInterval(am.ackTimestamp)).formattedDate(format: "h:mm:ss a"))")
								.foregroundColor(.gray)
								.font(.caption)

						} else {
							let ackErrorVal = RoutingError(rawValue: Int(am.ackError))
							Image(systemName: "square")
								.foregroundColor(.gray)
								.font(.caption)
							Text(ackErrorVal?.display ?? "Empty Ack Error")
								.foregroundColor(.gray)
								.font(.caption)
						}
					}
				}
			}
		}
		.navigationTitle("admin.log")
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			self.bleManager.context = context
		}
	}
}
