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
	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@EnvironmentObject
	private var bleManager: BLEManager
	@State
	private var node: NodeInfoEntity?
	@State
	private var visibleDevices: [Peripheral]
	@State
	private var invalidFirmwareVersion = false

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	var body: some View {
		NavigationStack {
			List {
				connection

				if !visibleDevices.isEmpty {
					visible
				}
			}
			.navigationTitle("Connection")
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ConnectedDevice()
			)
		}
		.onChange(of: bleManager.peripherals, initial: true) {
			Task {
				await loadPeripherals()
			}
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
		.onChange(of: bleManager.invalidVersion) {
			invalidFirmwareVersion = bleManager.invalidVersion
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
	private var connection: some View {
		Section {
			overallStatus
			connectedDevice
		}
	}

	@ViewBuilder
	private var overallStatus: some View {
		let on = bleManager.isSwitchedOn
		let connecting = bleManager.isConnecting
		let connected = bleManager.isConnected

		HStack(alignment: .top, spacing: 8) {
			if on {
				if connected {
					AvatarAbstract(
						icon: "checkmark.circle",
						color: .green,
						size: 64
					)
					.padding(.trailing, 10)
				}
				else if connecting {
					AvatarAbstract(
						icon: "hourglass.circle",
						color: .orange,
						size: 64
					)
					.padding(.trailing, 10)
				}
				else {
					AvatarAbstract(
						icon: "circle.dotted",
						color: .red,
						size: 64
					)
					.padding(.trailing, 10)
				}
			}
			else {
				AvatarAbstract(
					icon: "nosign",
					color: .gray,
					size: 64
				)
				.padding(.trailing, 10)
			}

			VStack(alignment: .leading) {
				Text("Bluetooth")
					.font(.title2)

				if on {
					if connected {
						Text("Connected")
							.font(detailInfoFont)
					}
					else if connecting {
						Text("Connecting")
							.font(detailInfoFont)
					}
					else {
						Text("Not Connected")
							.font(detailInfoFont)

						if bleManager.timeoutTimerCount > 0 {
							Text("Attempt: \(bleManager.timeoutTimerCount) of 10")
								.font(detailInfoFont)
								.foregroundColor(.gray)
						}

						if bleManager.lastConnectionError.count > 0 {
							Text(bleManager.lastConnectionError)
								.font(detailInfoFont)
								.foregroundColor(.gray)
						}
					}
				}
				else {
					Text("Bluetooth is Disabled")
						.font(detailInfoFont)
				}
			}
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: true) {
			Button(role: .destructive) {
				bleManager.cancelPeripheralConnection()
			} label: {
				Label(
					"Abort",
					systemImage: "antenna.radiowaves.left.and.right.slash"
				)
			}
		}
	}
	
	@ViewBuilder
	private var connectedDevice: some View {
		if
			let connectedPeripheral = bleManager.connectedPeripheral,
			(connectedPeripheral.peripheral.state == .connected || connectedPeripheral.peripheral.state == .connecting)
		{
			let node = nodes.first(where: { node in
				node.num == connectedPeripheral.num
			})

			HStack(alignment: .top, spacing: 8) {
				avatar()

				VStack(alignment: .leading, spacing: 8) {
					if node != nil {
						Text(connectedPeripheral.longName)
							.font(.title2)
					}
					else {
						Text("N/A")
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

					if let loRaConfig = node?.loRaConfig, loRaConfig.regionCode == RegionCodes.unset.rawValue {
						HStack(spacing: 8) {
							Image(systemName: "gear.badge.xmark")
								.font(detailInfoFont)
								.foregroundColor(.gray)

							Text("LoRa region is not set")
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
			.swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
			}
		}
	}

	@ViewBuilder
	private var visible: some View {
		Section("Visible Devices") {
			ForEach(visibleDevices) { peripheral in
				HStack(alignment: .top, spacing: 8) {
					let isPreferred = UserDefaults.preferredPeripheralId == peripheral.peripheral.identifier.uuidString

					avatar(isPreferred: isPreferred)

					HStack(spacing: 8) {
						SignalStrengthIndicator(
							signalStrength: peripheral.getSignalStrength(),
							size: 14,
							color: .gray
						)

						Text(peripheral.longName)
							.font(detailInfoFont)
							.foregroundColor(.gray)
					}
				}
				.swipeActions(edge: .leading, allowsFullSwipe: true) {
					Button {
						bleManager.connectTo(peripheral: peripheral.peripheral)
					} label: {
						Label(
							"Connect",
							systemImage: "antenna.radiowaves.left.and.right"
						)
					}
				}
			}
		}
	}

	init (node: NodeInfoEntity? = nil) {
		self.node = node
		self.visibleDevices = []

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

	@ViewBuilder
	private func avatar(
		isPreferred: Bool = false
	) -> some View {
		ZStack(alignment: .top) {
			if let node {
				AvatarNode(
					node,
					ignoreOffline: true,
					size: 64
				)
				.padding([.top, .bottom, .trailing], 10)
			}
			else {
				AvatarAbstract(
					icon: "questionmark",
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
			else if isPreferred {
				HStack(spacing: 0) {
					Spacer()
					Image(systemName: "star.circle.fill")
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

	private func loadPeripherals() async {
		let devices = bleManager.peripherals.filter { device in
			device.peripheral.state == CBPeripheralState.disconnected
		}

		visibleDevices = devices.sorted(by: {
			$0.name < $1.name
		})
	}

	private func fetchNodeInfo() async {
		let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
		fetchNodeInfoRequest.predicate = NSPredicate(
			format: "num == %lld",
			Int64(bleManager.connectedPeripheral?.num ?? -1)
		)

		node = try? context.fetch(fetchNodeInfoRequest).first
	}

	private func didDismissSheet() {
		bleManager.disconnectPeripheral(reconnect: false)
	}
}
