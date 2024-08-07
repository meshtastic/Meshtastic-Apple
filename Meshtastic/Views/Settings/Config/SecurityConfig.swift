//
//  Security.swift
//  Meshtastic
//
// Copyright(c) Garth Vander Houwen 8/7/24.
//

import Foundation
import SwiftUI
import CoreData
import MeshtasticProtobufs
import OSLog

struct SecurityConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State var hasChanges = false
	@State var isManaged = false
	@State var serialEnabled = true
	@State var debugLogEnabled = false
	@State var bluetoothLoggingEabled = false
	@State var adminChannelEnabled = false
	@State var publicKey = ""
	@State var privateKey = ""
	@State var adminKey = ""

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Security", config: \.securityConfig, node: node, onAppear: setSecurityValues)
			}
		}
	}
	func setSecurityValues() {
		self.isManaged = node?.securityConfig?.isManaged ?? false
		self.serialEnabled = node?.securityConfig?.serialEnabled ?? false
		self.debugLogEnabled = node?.securityConfig?.debugLogEnabled ?? false
		self.bluetoothLoggingEabled = node?.securityConfig?.bluetoothLoggingEabled ?? false
		self.adminChannelEnabled = node?.securityConfig?.adminChannelEnabled ?? false
		self.hasChanges = false
	}
}
