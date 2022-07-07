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
						
						Text("\(am.adminDescription ?? "Unknown") - \(Date(timeIntervalSince1970: TimeInterval(am.messageTimestamp)), style: .date) \(Date(timeIntervalSince1970: TimeInterval(am.messageTimestamp)), style: .time)")
							.font(.caption)
						
						if am.receivedACK {
							
							Image(systemName: "checkmark.square")
								.foregroundColor(.gray)
								.font(.caption)
							Text("Acknowledged: \(Date(timeIntervalSince1970: TimeInterval(am.messageTimestamp)), style: .time)")
								.foregroundColor(.gray)
								.font(.caption)
							
						} else {
							Image(systemName: "square")
								.foregroundColor(.gray)
								.font(.caption)
							Text("Not Acknowledged")
								.foregroundColor(.gray)
								.font(.caption)
						}
					}
				}
			}
		}
		.navigationTitle("Admin Message Log")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			self.bleManager.context = context
		}
	}
}
