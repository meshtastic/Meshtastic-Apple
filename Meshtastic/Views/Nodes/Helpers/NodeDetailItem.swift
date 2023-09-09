/*
 Abstract:
 A view showing the details for a node.
 */

import SwiftUI
import WeatherKit
import MapKit
import CoreLocation

struct NodeDetailItem: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.colorScheme) var colorScheme: ColorScheme
	@AppStorage("meshMapType") private var meshMapType = 0
	@AppStorage("meshMapShowNodeHistory") private var meshMapShowNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var meshMapShowRouteLines = false
	@State private var selectedMapLayer: MapLayer = .standard
	@State var waypointCoordinate: WaypointCoordinate?
	@State var editingWaypoint: Int = 0
	@State private var loadedWeather: Bool = false
	@State private var showingDetailsPopover = false
	@State private var showingForecast = false
	@State private var showingShutdownConfirm: Bool = false
	@State private var showingRebootConfirm: Bool = false
	@State private var customMapOverlay: MapViewSwiftUI.CustomMapOverlay? = MapViewSwiftUI.CustomMapOverlay(
		mapName: "offlinemap",
		tileType: "png",
		canReplaceMapContent: true
	)
	@ObservedObject var node: NodeInfoEntity
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>

	/// The current weather condition for the city.
	@State private var condition: WeatherCondition?
	@State private var temperature: Measurement<UnitTemperature>?
	@State private var humidity: Int?
	@State private var symbolName: String = "cloud.fill"

	@State private var attributionLink: URL?
	@State private var attributionLogo: URL?

	var body: some View {

		let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
		NavigationStack {
			GeometryReader { bounds in
				VStack {
					ScrollView {
						NodeInfoItem(node: node)
						if self.bleManager.connectedPeripheral != nil && node.metadata != nil {
							HStack {
								if node.metadata?.canShutdown ?? false {

									Button(action: {
										showingShutdownConfirm = true
									}) {
										Label("Power Off", systemImage: "power")
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.large)
									.padding()
									.confirmationDialog(
										"are.you.sure",
										isPresented: $showingShutdownConfirm
									) {
										Button("Shutdown Node?", role: .destructive) {
											if !bleManager.sendShutdown(fromUser: connectedNode!.user!, toUser: node.user!, adminIndex: connectedNode!.myInfo!.adminIndex) {
												print("Shutdown Failed")
											}
										}
									}
								}

								Button(action: {
									showingRebootConfirm = true
								}) {
									Label("reboot", systemImage: "arrow.triangle.2.circlepath")
								}
								.buttonStyle(.bordered)
								.buttonBorderShape(.capsule)
								.controlSize(.large)
								.padding()
								.confirmationDialog("are.you.sure",
													isPresented: $showingRebootConfirm
								) {
									Button("reboot.node", role: .destructive) {
										if !bleManager.sendReboot(fromUser: connectedNode!.user!, toUser: node.user!, adminIndex: connectedNode!.myInfo!.adminIndex) {
											print("Reboot Failed")
										}
									}
								}
							}
							.padding(5)
							Divider()
						}
					}
				}
				.edgesIgnoringSafeArea([.leading, .trailing])
				.sheet(item: $waypointCoordinate, content: { wpc in
					WaypointFormView(coordinate: wpc)
						.presentationDetents([.medium, .large])
						.presentationDragIndicator(.automatic)
				})
				.navigationBarTitle(String(node.user?.longName ?? "unknown".localized), displayMode: .inline)
				.navigationBarItems(trailing:
					ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
				})
			}
			.padding(.bottom, 2)
		}
	}
}
