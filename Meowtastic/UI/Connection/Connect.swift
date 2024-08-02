import CoreBluetooth
import CoreData
import CoreLocation
import MapKit
import OSLog
import SwiftUI

struct Connect: View {
	private let detailInfoFont = Font.system(size: 14, weight: .regular, design: .rounded)

	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@State
	private var node: NodeInfoEntity?
	@State
	private var isUnsetRegion = false
	@State
	private var invalidFirmwareVersion = false
	@State
	private var liveActivityStarted = false
	@State
	private var selectedPeripherialId = ""

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	private var visibleNodes: [Peripheral] {
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
					known

					if !visibleNodes.isEmpty {
						visible
					}
				}
				else {
					Text("Bluetooth Off")
						.foregroundColor(.red)
						.font(.title)
				}
			}
			.navigationTitle("Connection")
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ConnectedDevice()
			)
		}
		.onChange(of: bleManager.invalidVersion) {
			invalidFirmwareVersion = bleManager.invalidVersion
		}
		.onChange(of: bleManager.isConnected, initial: true) {
			Task {
				await fetchNodeInfo()
			}
		}
		.onChange(of: bleManager.isSubscribed) {
			Task {
				await fetchNodeInfo()
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
	private var known: some View {
		Section("Known Devices") {
			if
				let connectedPeripheral = bleManager.connectedPeripheral,
				connectedPeripheral.peripheral.state == .connected
			{
				let node = nodes.first(where: { node in
					node.num == connectedPeripheral.num
				})

				HStack(alignment: .top, spacing: 8) {
					avatar

					VStack(alignment: .leading) {
						if node != nil {
							Text(connectedPeripheral.longName)
								.font(.title2)
						}

						HStack(spacing: 8) {
							SignalStrengthIndicator(
								signalStrength: connectedPeripheral.getSignalStrength(),
								size: 14,
								color: .gray
							)

							if let name = bleManager.connectedPeripheral?.peripheral.name {
								Text(name)
									.font(detailInfoFont)
									.foregroundColor(.gray)
							}
						}

						HStack(spacing: 8) {
							if let hwModel = node?.user?.hwModel {
								Text(hwModel)
									.font(detailInfoFont)
									.foregroundColor(.gray)
							}

							if let version = node?.metadata?.firmwareVersion {
								Text("v\(version)")
									.font(detailInfoFont)
									.foregroundColor(.gray)
							}
						}
					}
				}
				.swipeActions(edge: .trailing) {
					Button(role: .destructive) {
						if
							let connectedPeripheral = bleManager.connectedPeripheral,
							connectedPeripheral.peripheral.state == .connected
						{
							bleManager.disconnectPeripheral(reconnect: false)
						}
					} label: {
						Label(
							"Disconnect",
							systemImage: "antenna.radiowaves.left.and.right.slash"
						)
					}

					if let user = node?.user, let myInfo = node?.myInfo {
						Button(role: .destructive) {
							if !bleManager.sendShutdown(
								fromUser: user,
								toUser: user,
								adminIndex: myInfo.adminIndex
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
								systemImage: "globe.europe.africa.fill"
							)
							.font(.title)
							.foregroundColor(.red)
						}
					}
				}
			}
			else {
				if bleManager.isConnecting {
					HStack(alignment: .top, spacing: 8) {
						avatar

						VStack(alignment: .leading) {
							Text("Connecting")
								.font(.title2)

							if bleManager.timeoutTimerCount > 0 {
								Text("Attempt: \(bleManager.timeoutTimerCount) of 10")
									.font(detailInfoFont)
									.foregroundColor(.gray)
							}
						}
					}
					.swipeActions(edge: .trailing) {
						Button(role: .destructive) {
							bleManager.cancelPeripheralConnection()
						} label: {
							Label(
								"Disconnect",
								systemImage: "antenna.radiowaves.left.and.right.slash"
							)
						}
					}
				}
				else {
					if bleManager.lastConnectionError.count > 0 {
						Text(bleManager.lastConnectionError)
							.font(detailInfoFont)
							.foregroundColor(.red)
					}

					HStack {
						Image(systemName: "antenna.radiowaves.left.and.right.slash")
							.resizable()
							.symbolRenderingMode(.hierarchical)
							.foregroundColor(.red)
							.frame(width: 60, height: 60)
							.padding(.trailing)

						Text("Not Connected")
							.font(.title3)
					}
				}
			}
		}
	}

	@ViewBuilder
	private var visible: some View {
		Section(
			header: Text("Visible Nodes")
				.font(.title)
		) {
			ForEach(visibleNodes) { peripheral in
				HStack {
					if UserDefaults.preferredPeripheralId == peripheral.peripheral.identifier.uuidString {
						Image(systemName: "star.fill")
							.imageScale(.large)
							.foregroundColor(.yellow)
							.padding(.trailing)
					}
					else {
						Image(systemName: "circle.fill")
							.imageScale(.large)
							.foregroundColor(.gray)
							.padding(.trailing)
					}

					Spacer()

					SignalStrengthIndicator(
						signalStrength: peripheral.getSignalStrength(),
						size: 64
					)
				}
			}
		}
	}

	@ViewBuilder
	private var avatar: some View {
		ZStack(alignment: .top) {
			if let node {
				AvatarNode(
					node,
					size: 64
				)
				.padding([.top, .bottom, .trailing], 10)
			}
			else {
				AvatarAbstract(
					size: 64
				)
				.padding([.top, .bottom, .trailing], 10)
			}

			if bleManager.isConnecting {
				HStack(spacing: 0) {
					Spacer()
					Image(systemName: "magnifyingglass.circle.fill")
						.font(.system(size: 24))
						.foregroundColor(colorScheme == .dark ? .white : .gray)
						.background(
							Circle()
								.foregroundColor(colorScheme == .dark ? .black : .white)
						)
				}
			}
			else if bleManager.isConnected, !bleManager.isSubscribed {
				HStack(spacing: 0) {
					Spacer()
					Image(systemName: "hourglass.circle.fill")
						.font(.system(size: 24))
						.foregroundColor(colorScheme == .dark ? .white : .gray)
						.background(
							Circle()
								.foregroundColor(colorScheme == .dark ? .black : .white)
						)
				}
			}
			else if bleManager.isSubscribed {
				HStack(spacing: 0) {
					Spacer()
					Image(systemName: "checkmark.circle.fill")
						.font(.system(size: 24))
						.foregroundColor(colorScheme == .dark ? .white : .gray)
						.background(
							Circle()
								.foregroundColor(colorScheme == .dark ? .black : .white)
						)
				}
			}
			else {
				HStack(spacing: 0) {
					Spacer()
					Image(systemName: "exclamationmark.circle.fill")
						.font(.system(size: 24))
						.foregroundColor(colorScheme == .dark ? .white : .gray)
						.background(
							Circle()
								.foregroundColor(colorScheme == .dark ? .black : .white)
						)
				}
			}
		}
		.frame(width: 80, height: 80)
	}

	init (node: NodeInfoEntity? = nil) {
		self.node = node

		let notificationCenter = UNUserNotificationCenter.current()

		notificationCenter.getNotificationSettings(
			completionHandler: { settings in
				if settings.authorizationStatus == .notDetermined {
					UNUserNotificationCenter.current().requestAuthorization(
						options: [.alert, .badge, .sound]
					) { success, error in
						if success {
							Logger.services.info("Notifications are all set!")
						}
						else if let error = error {
							Logger.services.error("\(error.localizedDescription)")
						}
					}
				}
			}
		)
	}

	private func fetchNodeInfo() async {
		let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
		fetchNodeInfoRequest.predicate = NSPredicate(
			format: "num == %lld",
			Int64(bleManager.connectedPeripheral?.num ?? -1)
		)

		node = try? context.fetch(fetchNodeInfoRequest).first

		if bleManager.isSubscribed, UserDefaults.preferredPeripheralId.count > 0 {
			if let loRaConfig = node?.loRaConfig, loRaConfig.regionCode == RegionCodes.unset.rawValue {
				isUnsetRegion = true
			}
			else {
				isUnsetRegion = false
			}
		}
	}

	private func didDismissSheet() {
		bleManager.disconnectPeripheral(reconnect: false)
	}
}
