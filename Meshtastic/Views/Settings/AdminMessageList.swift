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
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmmssa", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mm:ss a")
		List {
			if user != nil {

				ForEach( user!.adminMessageList.reversed() ) { am in

					VStack(alignment: .leading) {

						Text("\(am.adminDescription ?? NSLocalizedString("unknown", comment: "Unknown"))")
							.font(.caption)

						Text("Sent \(Date(timeIntervalSince1970: TimeInterval(am.messageTimestamp)).formattedDate(format: dateFormatString))")
							.foregroundColor(.gray)
							.font(.caption2)

						HStack(spacing: 0) {
							let ackErrorVal = RoutingError(rawValue: Int(am.ackError))

							if am.ackTimestamp > 0 {
								if am.realACK {
									
									Text(ackErrorVal?.display ?? "Empty Ack Error")
										.foregroundColor(am.receivedACK ? .gray : .red)
										.font(.caption2)
								} else {
									Text("Implicit ACK from Unknown Node")
										.foregroundColor(.orange)
										.font(.caption2)
								}
							}

							if am.receivedACK && am.ackTimestamp > 0 {
								Text(" \(Date(timeIntervalSince1970: TimeInterval(am.ackTimestamp)).formattedDate(format: "h:mm:ss a"))")
									.foregroundColor(am.realACK ? .gray : .orange)
									.font(.caption2)
							}
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
