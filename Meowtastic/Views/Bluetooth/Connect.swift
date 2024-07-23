import SwiftUI
import MapKit
import CoreData
import CoreLocation
import CoreBluetooth
import OSLog

struct Connect: View {
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager

	@State
	var node: NodeInfoEntity?
	@State
	var isUnsetRegion = false
	@State
	var invalidFirmwareVersion = false
	@State
	var liveActivityStarted = false
	@State
	var selectedPeripherialId = ""

	private var peripherals: [Peripheral] {
		let peripherals = bleManager.peripherals.filter { device in
			device.peripheral.state == CBPeripheralState.disconnected
		}

		return peripherals.sorted(by: {
			$0.name < $1.name
		})
	}

	var body: some View {
		NavigationStack {
			List {
				if bleManager.isSwitchedOn {
					connectedDevice

					if !self.bleManager.isConnected && !peripherals.isEmpty {
						visibleDevices
					}
				} else {
					Text("Bluetooth Off")
						.foregroundColor(.red)
						.font(.title)
				}
			}
			.navigationTitle("Bluetooth")
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ConnectedDevice(ble: bleManager)
			)
		}
		.onChange(of: bleManager.invalidVersion) {
			invalidFirmwareVersion = self.bleManager.invalidVersion
		}
		.onChange(of: bleManager.isSubscribed) {
			if UserDefaults.preferredPeripheralId.count > 0 && bleManager.isSubscribed {
				let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
				fetchNodeInfoRequest.predicate = NSPredicate(
					format: "num == %lld",
					Int64(bleManager.connectedPeripheral?.num ?? -1)
				)

				do {
					node = try context.fetch(fetchNodeInfoRequest).first

					if let loRaConfig = node?.loRaConfig, loRaConfig.regionCode == RegionCodes.unset.rawValue {
						isUnsetRegion = true
					} else {
						isUnsetRegion = false
					}
				} catch {
					Logger.data.error("💥 Error fetching node info: \(error.localizedDescription)")
				}
			}
		}
		.sheet(
			isPresented: $invalidFirmwareVersion,
			onDismiss: didDismissSheet
		) {
			InvalidVersion(
				minimumVersion: bleManager.minimumVersion,
				version: bleManager.connectedVersion
			)
			.presentationDetents([.large])
			.presentationDragIndicator(.automatic)
		}
	}

	@ViewBuilder
	private var connectedDevice: some View {
		Section(
			header: Text("Known Devices")
				.font(.title)
		) {
			if
				let connectedPeripheral = bleManager.connectedPeripheral,
				connectedPeripheral.peripheral.state == .connected
			{
				HStack {
					VStack(alignment: .center) {
						Avatar(
							node?.user?.shortName ?? "?",
							background: Color(UIColor(hex: UInt32(node?.num ?? 0))),
							size: 90
						)
					}
					.padding(.trailing)

					VStack(alignment: .leading) {
						if node != nil {
							Text(connectedPeripheral.longName).font(.title2)
						}

						HStack {
							Text("Name:")
								.font(.callout)

							Text(bleManager.connectedPeripheral?.peripheral.name ?? "N/A")
								.font(.callout)
								.foregroundColor(Color.gray)
						}

						if node != nil {
							HStack {
								Text("Firmware:")
									.font(.callout)

								Text(node?.metadata?.firmwareVersion ?? "N/A")
									.font(.callout)
									.foregroundColor(Color.gray)
							}
						}

						if bleManager.isSubscribed {
							Text("subscribed")
								.font(.callout)
								.foregroundColor(.green)
						} else {
							HStack {
								Image(systemName: "square.stack.3d.down.forward")
									.symbolRenderingMode(.multicolor)
									.symbolEffect(
										.variableColor.reversing.cumulative,
										options: .repeat(20).speed(3)
									)
									.foregroundColor(.orange)

								Text("communicating")
									.font(.callout)
									.foregroundColor(.orange)
							}
						}
					}
				}
				.font(.caption)
				.foregroundColor(Color.gray)
				.swipeActions {
					Button(role: .destructive) {
						if
							let connectedPeripheral = bleManager.connectedPeripheral,
							connectedPeripheral.peripheral.state == .connected
						{
							bleManager.disconnectPeripheral(reconnect: false)
						}
					} label: {
						Label(
							"disconnect",
							systemImage: "antenna.radiowaves.left.and.right.slash"
						)
					}
				}
				.contextMenu {
					if node != nil {
						Text("Num: \(String(node!.num))")
						Text("Short Name: \(node?.user?.shortName ?? "N/A")")
						Text("Long Name: \(node?.user?.longName ?? "N/A")")
						Text("RSSI: \(connectedPeripheral.rssi)")

						Button {
							if !bleManager.sendShutdown(
								fromUser: node!.user!,
								toUser: node!.user!,
								adminIndex: node!.myInfo!.adminIndex
							) {
								Logger.mesh.error("Shutdown Failed")
							}
						} label: {
							Label("Power Off", systemImage: "power")
						}
					}
				}

				if isUnsetRegion {
					HStack {
						NavigationLink {
							LoRaConfig(node: node)
						} label: {
							Label(
								"Set Region",
								systemImage: "globe.americas.fill"
							)
							.foregroundColor(.red)
							.font(.title)
						}
					}
				}
			} else {
				if bleManager.isConnecting {
					HStack {
						Image(systemName: "antenna.radiowaves.left.and.right")
							.resizable()
							.symbolRenderingMode(.hierarchical)
							.foregroundColor(.orange)
							.frame(width: 60, height: 60)
							.padding(.trailing)

						if bleManager.timeoutTimerCount == 0 {
							Text("Connecting")
								.font(.title2)
								.foregroundColor(.orange)
						} else {
							VStack {
								Text("Connection Attempt \(bleManager.timeoutTimerCount) of 10")
									.font(.callout)
									.foregroundColor(.orange)
							}
						}
					}
					.padding()
					.swipeActions {
						Button(role: .destructive) {
							bleManager.cancelPeripheralConnection()
						} label: {
							Label(
								"Disconnect",
								systemImage: "antenna.radiowaves.left.and.right.slash"
							)
						}
					}
				} else {
					if bleManager.lastConnectionError.count > 0 {
						Text(bleManager.lastConnectionError).font(.callout).foregroundColor(.red)
					}

					HStack {
						Image(systemName: "antenna.radiowaves.left.and.right.slash")
							.resizable()
							.symbolRenderingMode(.hierarchical)
							.foregroundColor(.red)
							.frame(width: 60, height: 60)
							.padding(.trailing)

						Text("Not Connected").font(.title3)
					}
					.padding()
				}
			}
		}
		.textCase(nil)
	}

	@ViewBuilder
	private var visibleDevices: some View {
		Section(
			header: Text("Visible Nodes")
				.font(.title)
		) {
			ForEach(peripherals) { peripheral in
				HStack {
					if UserDefaults.preferredPeripheralId == peripheral.peripheral.identifier.uuidString {
						Image(systemName: "star.fill")
							.imageScale(.large).foregroundColor(.yellow)
							.padding(.trailing)
					} else {
						Image(systemName: "circle.fill")
							.imageScale(.large).foregroundColor(.gray)
							.padding(.trailing)
					}

					Button(action: {
						if
							UserDefaults.preferredPeripheralId.count > 0
								&& peripheral.peripheral.identifier.uuidString != UserDefaults.preferredPeripheralId
						{
							if
								let connectedPeripheral = bleManager.connectedPeripheral,
								connectedPeripheral.peripheral.state == CBPeripheralState.connected
							{
								bleManager.disconnectPeripheral()
							}

							guard let url = FileManager.default.urls(
								for: .documentDirectory,
								in: .userDomainMask
							).first else {
								Logger.data.error("nil File path for back")
								return
							}

							do {
								try Persistence.shared.copyPersistentStores(
									to: url
										.appendingPathComponent("backup")
										.appendingPathComponent("\(UserDefaults.preferredPeripheralNum)"),
									overwriting: true
								)

								Logger.data.notice("🗂️ Made a core data backup to backup/\(UserDefaults.preferredPeripheralNum)")
							} catch {
								Logger.data.error("🗂️ Core data backup copy error: \(error, privacy: .public)")
							}
							clearCoreDataDatabase(context: context, includeRoutes: false)
						}

						UserDefaults.preferredPeripheralId = selectedPeripherialId
						self.bleManager.connectTo(peripheral: peripheral.peripheral)
					}) {
						Text(peripheral.name).font(.callout)
					}

					Spacer()

					VStack {
						SignalStrengthIndicator(signalStrength: peripheral.getSignalStrength())
					}
				}
			}
		}
	}

	init () {
		let notificationCenter = UNUserNotificationCenter.current()

		notificationCenter.getNotificationSettings(
			completionHandler: { settings in
				if settings.authorizationStatus == .notDetermined {
					UNUserNotificationCenter.current().requestAuthorization(
						options: [.alert, .badge, .sound]
					) { success, error in
						if success {
							Logger.services.info("Notifications are all set!")
						} else if let error = error {
							Logger.services.error("\(error.localizedDescription)")
						}
					}
				}
			}
		)
	}

	private func didDismissSheet() {
		bleManager.disconnectPeripheral(reconnect: false)
	}
}
