import Combine
import FirebaseAnalytics
import Foundation
import MapKit
import OSLog
import SwiftProtobuf
import SwiftUI

struct AppSettings: View {
	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@State
	private var isPresentingCoreDataResetConfirm = false
	@State
	private var isPresentingDeleteMapTilesConfirm = false

	var body: some View {
		VStack {
			Form {
				Section(header: Text("App Settings")) {
					Button("Open Settings", systemImage: "gear") {
						// Get the settings URL and open it
						if let url = URL(string: UIApplication.openSettingsURLString) {
							UIApplication.shared.open(url)
						}
					}
				}
			}
		}
		.navigationTitle("App Settings")
		.navigationBarItems(
			trailing: ConnectedDevice()
		)
		.onAppear {
			Analytics.logEvent(AnalyticEvents.optionsAppSettings.id, parameters: nil)
		}
	}
}
