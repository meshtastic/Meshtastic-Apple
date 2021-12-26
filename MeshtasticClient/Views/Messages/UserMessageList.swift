//
//  UserMessageList.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import SwiftUI
import CoreData

struct UserMessageList: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	var user: UserEntity

    var body: some View {

		HStack {

			List {

				ScrollViewReader { _ in

					ScrollView {

						if user.receivedMessages != nil && user.receivedMessages!.count > 0 {

							ForEach( user.receivedMessages?.array as! [MessageEntity], id: \.self) { (_: MessageEntity) in

							}
						}
					}
				}
			}
		}
		.navigationViewStyle(.stack)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {

				HStack {

					CircleText(text: user.shortName ?? "???", color: .blue).fixedSize()
					Text(user.longName ?? "Unknown").foregroundColor(.gray).font(.caption2).fixedSize()
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {

					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "???")
				}
			}
		}
    }
}
