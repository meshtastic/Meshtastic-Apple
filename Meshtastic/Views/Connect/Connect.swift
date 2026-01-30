//
//  Connect.swift
//  Meshtastic Apple
//
//  Copyright(c) Garth Vander Houwen 8/18/21.
//

import SwiftUI
import MapKit
import CoreData
import CoreLocation
import CoreBluetooth
import OSLog
import TipKit
#if canImport(ActivityKit)
import ActivityKit
#endif

struct Connect: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.colorScheme) private var colorScheme
	@State var router: Router
	@State var node: NodeInfoEntity?
	@State var isUnsetRegion = false
	@State var invalidFirmwareVersion = false
	@State var liveActivityStarted = false
	@ObservedObject var manualConnections = ManualConnectionList.shared
	
	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				List {
					Section {
						if let connectedDevice = accessoryManager.activeConnection?.device,
						   accessoryManager.isConnected || accessoryManager.isConnecting {
							TipView(ConnectionTip(), arrowEdge: .bottom)
								.tipViewStyle(PersistentTip())
								.tipBackground(colorScheme == .dark ? Color(.systemBackground) : Color(.secondarySystemBackground))
								.listRowSeparator(.hidden)
							VStack(alignment: .leading) {
								HStack {
									VStack(alignment: .center) {
										CircleText(text: node?.user?.shortName?.addingVariationSelectors ?? "?", color: Color(UIColor(hex: UInt32(node?.num ?? 0))), circleSize: 90)
											.padding(.trailing, 5)
										if node?.latestDeviceMetrics != nil {
											BatteryCompact(batteryLevel: node?.latestDeviceMetrics?.batteryLevel ?? 0, font: .caption, iconFont: .callout, color: .accentColor)
												.padding(.trailing, 5)
										}
									}
									.padding(.trailing)
									VStack(alignment: .leading) {
										if node != nil {
											HStack {
												Text(connectedDevice.longName?.addingVariationSelectors ?? "Unknown".localized).font(.title2)
												if connectedDevice.wasRestored {
													Circle()
														.fill(Color.gray)
														.frame(width: 8, height: 8)
												}
											}
										}
										Text("Connection Name").font(.callout)+Text(": \(connectedDevice.name.addingVariationSelectors)")
											.font(.callout).foregroundColor(Color.gray)
										HStack(alignment: .firstTextBaseline) {
											TransportIcon(transportType: connectedDevice.transportType)
											if connectedDevice.transportType == .ble {
												connectedDevice.getSignalStrength().map { SignalStrengthIndicator(signalStrength: $0, width: 5, height: 20) }
											}
											Spacer()
										}
										.padding(0)
										if node != nil {
											Text("Firmware Version").font(.callout)+Text(": \(node?.metadata?.firmwareVersion ?? "Unknown".localized)")
												.font(.callout).foregroundColor(Color.gray)
										}
										switch accessoryManager.state {
										case .subscribed:
											Text("Subscribed").font(.callout)
												.foregroundColor(.green)
										case .retrievingDatabase(let nodeCount):
											HStack {
												Image(systemName: "square.stack.3d.down.forward")
													.symbolRenderingMode(.multicolor)
													.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
													.foregroundColor(.teal)
												if let expectedNodeDBSize = accessoryManager.expectedNodeDBSize {
													if UIDevice.current.userInterfaceIdiom == .phone {
														VStack(alignment: .leading, spacing: 2.0) {
															Text("Retrieving nodes").font(.callout)
																.foregroundColor(.teal)
															ProgressView(value: Double(nodeCount), total: Double(expectedNodeDBSize))
														}
													} else {
														// iPad/Mac with more space, show progress bar AFTER the label
														HStack {
															Text("Retrieving nodes").font(.callout)
																.foregroundColor(.teal)
															ProgressView(value: Double(nodeCount), total: Double(expectedNodeDBSize))
														}
													}
													
												} else {
													Text("Retrieving nodes \(nodeCount)").font(.callout)
														.foregroundColor(.teal)
												}
											}
										case .communicating:
											HStack {
												Image(systemName: "square.stack.3d.down.forward")
													.symbolRenderingMode(.multicolor)
													.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
													.foregroundColor(.orange)
												Text("Communicating").font(.callout)
													.foregroundColor(.orange)
											}
										case .retrying(let attempt):
											HStack {
												Image(systemName: "square.stack.3d.down.forward")
													.symbolRenderingMode(.multicolor)
													.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
													.foregroundColor(.orange)
												Text("Retrying (attempt \(attempt))").font(.callout)
													.foregroundColor(.orange)
											}
										default:
											EmptyView()
										}
									}
								}
							}
							.font(.caption)
							.foregroundColor(Color.gray)
							.padding([.top])
							.swipeActions {
								if accessoryManager.allowDisconnect {
									Button(role: .destructive) {
										Task {
											try await accessoryManager.disconnect()
										}
									} label: {
										Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
									}.disabled(!accessoryManager.allowDisconnect)
								}
							}
							.contextMenu {
								
								if node != nil {
									Label("\(String(node!.num))", systemImage: "number")
#if !targetEnvironment(macCatalyst)
									if accessoryManager.state == .subscribed {
										Button {
											if !liveActivityStarted {
#if canImport(ActivityKit)
												Logger.services.info("Start live activity.")
												startNodeActivity()
#endif
											} else {
#if canImport(ActivityKit)
												Logger.services.info("Stop live activity.")
												endActivity()
#endif
											}
										} label: {
											Label("Mesh Live Activity", systemImage: liveActivityStarted ? "stop" : "play")
										}
									}
#endif
									if accessoryManager.allowDisconnect {
										Button(role: .destructive) {
											if accessoryManager.allowDisconnect {
												Task {
													try await accessoryManager.disconnect()
												}
											}
										} label: {
											Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
										}
										Button(role: .destructive) {
											Task {
												do {
													try await accessoryManager.sendShutdown(fromUser: node!.user!, toUser: node!.user!)
												} catch {
													Logger.mesh.error("Shutdown Failed: \(error)")
												}
											}
											
										} label: {
											Label("Power Off", systemImage: "power")
										}
									}
								}
							}
							if isUnsetRegion {
								HStack {
									NavigationLink {
										LoRaConfig(node: node)
									} label: {
										Label("Set LoRa Region", systemImage: "globe.americas.fill")
											.foregroundColor(.red)
											.font(.title)
									}
								}
							}
						} else {
							if accessoryManager.isConnecting {
								HStack {
									Image(systemName: "antenna.radiowaves.left.and.right")
										.resizable()
										.symbolRenderingMode(.hierarchical)
										.foregroundColor(.orange)
										.frame(width: 60, height: 60)
										.padding(.trailing)
									switch accessoryManager.state {
									case .connecting, .communicating:
										Text("Connecting . .")
											.font(.title2)
											.foregroundColor(.orange)
									case .retrievingDatabase:
										Text("Retreiving nodes . .")
											.font(.callout)
											.foregroundColor(.orange)
									case .retrying(let attempt):
										Text("Connection Attempt \(attempt) of 10")
											.font(.callout)
											.foregroundColor(.orange)
									default:
										EmptyView()
									}
								}
								.padding()
								.swipeActions {
									if accessoryManager.allowDisconnect {
										Button(role: .destructive) {
											Task {
												try await accessoryManager.disconnect()
											}
										} label: {
											Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
										}.disabled(!accessoryManager.allowDisconnect)
									}
								}
								
							} else {
								
								if let lastError = accessoryManager.lastConnectionError as? Error {
									Text(lastError.localizedDescription).font(.callout).foregroundColor(.red)
								}
								HStack {
									Image("custom.link.slash")
										.resizable()
										.symbolRenderingMode(.hierarchical)
										.foregroundColor(.red)
										.frame(width: 60, height: 60)
										.padding(.trailing)
									Text("No device connected").font(.title3)
								}
								.padding()
							}
						}
					}
					.textCase(nil)
					
					if !(accessoryManager.isConnected || accessoryManager .isConnecting) {
						Group {
							Section(header: HStack {
								Text("Available Radios").font(.title)
								Spacer()
								ManualConnectionMenu()
							}) {
								ForEach(accessoryManager.devices.sorted(by: { $0.name < $1.name })) { device in
									DeviceConnectRow(device: device)
								}
							}
							if manualConnections.connectionsList.count > 0 {
								Section(header: Text("Manual Connections").font(.title)) {
									ForEach(manualConnections.connectionsList) { device in
										DeviceConnectRow(device: device)
#if targetEnvironment(macCatalyst)
											.contextMenu {
												Button {
													manualConnections.remove(device: device)
												} label: {
													Label("Delete", systemImage: "trash")
												}
											}
#endif
									}.onDelete { offsets in
										manualConnections.remove(atOffsets: offsets)
									}

								}
							}
						}
						.textCase(nil)
					}
				}
				.scrollContentBackground(.hidden)
				HStack(alignment: .center) {
					Spacer()
#if targetEnvironment(macCatalyst)
					// TODO: should this be allowDisconnect?
					if accessoryManager.allowDisconnect {
						Button(role: .destructive, action: {
							if accessoryManager.allowDisconnect {
								Task {
									try await accessoryManager.disconnect()
								}
							}
						}) {
							Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.padding()
					}
#endif
					Spacer()
				}
				.padding(.bottom, 10)
				
			}
			.background(Color(.systemGroupedBackground))
			.navigationTitle("Connect")
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ZStack {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?",
						mqttProxyConnected: accessoryManager.mqttProxyConnected,
						mqttTopic: accessoryManager.mqttManager.topic
						
					)
				}
			)
			
		}
		// TODO: REMOVING VERSION STUFF?
		//		.sheet(isPresented: $invalidFirmwareVersion, onDismiss: didDismissSheet) {
		//			InvalidVersion(minimumVersion: accessoryManager.minimumVersion, version: accessoryManager.activeConnection?.device.firmwareVersion ?? "?.?.?")
		//				.presentationDetents([.large])
		//				.presentationDragIndicator(.automatic)
		//		}
		//		.onChange(of: accessoryManager) {
		//			invalidFirmwareVersion = self.bleManager.invalidVersion
		//		}
		.onChange(of: self.accessoryManager.state) { _, state in
			
			if let deviceNum = accessoryManager.activeDeviceNum, UserDefaults.preferredPeripheralId.count > 0 && state == .subscribed {
				
				let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
				fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", deviceNum)
				
				do {
					node = try context.fetch(fetchNodeInfoRequest).first
					if let loRaConfig = node?.loRaConfig, loRaConfig.regionCode == RegionCodes.unset.rawValue {
						isUnsetRegion = true
					} else {
						isUnsetRegion = false
					}
				} catch {
					Logger.data.error("💥 Error fetching node info: \(error.localizedDescription, privacy: .public)")
				}
			}
		}
	}
#if !targetEnvironment(macCatalyst)
#if canImport(ActivityKit)
	func startNodeActivity() {
		liveActivityStarted = true
		// 15 Minutes Local Stats Interval
		let timerSeconds = 900
		let localStats = node?.telemetries?.filtered(using: NSPredicate(format: "metricsType == 4"))
		let mostRecent = localStats?.lastObject as? TelemetryEntity
		
		let activityAttributes = MeshActivityAttributes(nodeNum: Int(node?.num ?? 0), name: node?.user?.longName?.addingVariationSelectors ?? "unknown")
		
		let future = Date(timeIntervalSinceNow: Double(timerSeconds))
		let initialContentState = MeshActivityAttributes.ContentState(uptimeSeconds: UInt32(mostRecent?.uptimeSeconds ?? 0),
																	  channelUtilization: mostRecent?.channelUtilization ?? 0.0,
																	  airtime: mostRecent?.airUtilTx ?? 0.0,
																	  sentPackets: UInt32(mostRecent?.numPacketsTx ?? 0),
																	  receivedPackets: UInt32(mostRecent?.numPacketsRx ?? 0),
																	  badReceivedPackets: UInt32(mostRecent?.numPacketsRxBad ?? 0),
																	  dupeReceivedPackets: UInt32(mostRecent?.numRxDupe ?? 0),
																	  packetsSentRelay: UInt32(mostRecent?.numTxRelay ?? 0),
																	  packetsCanceledRelay: UInt32(mostRecent?.numTxRelayCanceled ?? 0),
																	  nodesOnline: UInt32(mostRecent?.numOnlineNodes ?? 0),
																	  totalNodes: UInt32(mostRecent?.numTotalNodes ?? 0),
																	  timerRange: Date.now...future)
		
		let activityContent = ActivityContent(state: initialContentState, staleDate: Calendar.current.date(byAdding: .minute, value: 15, to: Date())!)
		
		do {
			let myActivity = try Activity<MeshActivityAttributes>.request(attributes: activityAttributes, content: activityContent,
																		  pushType: nil)
			Logger.services.info("Requested MyActivity live activity. ID: \(myActivity.id)")
		} catch {
			Logger.services.error("Error requesting live activity: \(error.localizedDescription, privacy: .public)")
		}
	}
	
	func endActivity() {
		liveActivityStarted = false
		Task {
			for activity in Activity<MeshActivityAttributes>.activities where activity.attributes.nodeNum == node?.num ?? 0 {
				await activity.end(nil, dismissalPolicy: .immediate)
			}
		}
	}
#endif
#endif
	func didDismissSheet() {
		// bleManager.disconnectPeripheral(reconnect: false)
		Task {
			try await accessoryManager.disconnect()
		}
	}
}

struct TransportIcon: View {
	var transportType: TransportType
	@EnvironmentObject var accessoryManager: AccessoryManager
	
	var body: some View {
		let transport = accessoryManager.transportForType(transportType)
		return HStack(spacing: 3.0) {
			if let icon = transport?.type.icon {
				icon
					.font(.title2)
					.foregroundColor(transport?.type == .ble ? Color.accentColor : Color.primary)
			} else {
				Image(systemName: "questionmark")
					.font(.title2)
			}
			Text(transport?.type.rawValue ?? "Unknown".localized)
				.font(.title3)
		}
	}
}

struct ManualConnectionMenu: View {

	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.managedObjectContext) var context

	private struct IterableTransport: Identifiable {
		let id: UUID
		let icon: Image
		let title: String
		let transport: any Transport
	}
	
	private var transports: [IterableTransport]
	
	init() {
		self.transports = AccessoryManager.shared.transports.filter { $0.supportsManualConnection}.map { transport in
			IterableTransport(id: UUID(), icon: transport.type.icon, title: transport.type.rawValue, transport: transport)
		}
	}
	
	@State private var selectedTransport: IterableTransport?
	@State private var showAlert: Bool = false
	@State private var connectionString = ""
	@State var presentingSwitchPreferredPeripheral = false
	@State var deviceForManualConnection: Device?

	var body: some View {
		Menu {
			ForEach(transports) { transport in
				Button {
					self.selectedTransport = transport
					self.showAlert = true
				} label: {
					Label(title: { Text(transport.title)}, icon: { transport.icon })
				}
			}
		} label: {
			Label("Manual", systemImage: "plus")
		}.alert("Manual connection string", isPresented: $showAlert, presenting: selectedTransport) { selectedTransport in
			// This continues to be quick and dirty. A better system is needed.
			TextField("Enter hostname[:port]", text: $connectionString)
				.keyboardType(.URL)
				.autocapitalization(.none)
				.disableAutocorrection(true)
				.onChange(of: connectionString) { _, newValue in
					// Filter to only allow valid characters for hostname/IP:port
					let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:")
					let filtered = String(newValue.unicodeScalars.filter { allowedCharacters.contains($0) })
					if filtered != newValue {
						connectionString = filtered
					}
				}
			
			Button("OK", action: {
				if !connectionString.isEmpty {
					if let device = selectedTransport.transport.device(forManualConnection: connectionString) {
						if UserDefaults.preferredPeripheralId == device.id.uuidString {
							Task {
								try await selectedTransport.transport.manuallyConnect(toDevice: device)
							}
						} else {
							deviceForManualConnection = device
							presentingSwitchPreferredPeripheral = true
						}
					}
				}
			})
		}.confirmationDialog("Connecting to a new radio will clear all app data on the phone.", isPresented: $presentingSwitchPreferredPeripheral, titleVisibility: .visible) {
			Button("Connect to new radio?", role: .destructive) {
				Task {
					if let device = deviceForManualConnection {
						UserDefaults.preferredPeripheralId = device.id.uuidString
						UserDefaults.preferredPeripheralNum = 0
						if accessoryManager.allowDisconnect {
							try await accessoryManager.disconnect()
						}
						await MeshPackets.shared.clearCoreDataDatabase(includeRoutes: false)
						clearNotifications()
						try await selectedTransport?.transport.manuallyConnect(toDevice: device)
						
						// Clean up just in case
						deviceForManualConnection = nil
					}
				}
			}
		}
	}
}

struct DeviceConnectRow: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State var presentingSwitchPreferredPeripheral = false
	let device: Device
	
	var body: some View {
		HStack {
			if UserDefaults.preferredPeripheralId == device.id.uuidString {
				Image(systemName: "star.fill")
					.imageScale(.large).foregroundColor(.yellow)
					.padding(.trailing)
			} else {
				Image(systemName: "circle.fill")
					.imageScale(.large).foregroundColor(.gray)
					.padding(.trailing)
			}
			VStack(alignment: .leading) {
				Button(action: {
					if UserDefaults.preferredPeripheralId.count > 0 && device.id.uuidString != UserDefaults.preferredPeripheralId {
						if accessoryManager.allowDisconnect {
							Task { try await accessoryManager.disconnect() }
						}
						presentingSwitchPreferredPeripheral = true
					} else {
						Task {
							try? await accessoryManager.connect(to: device)
						}
					}
				}) {
					Text(device.name).font(.callout)
				}
				// Show transport type
#if !targetEnvironment(macCatalyst)
				HStack(alignment: .center){
					TransportIcon(transportType: device.transportType)
					if device.isManualConnection && (device.longName != nil || device.shortName != nil) {
						VStack (alignment: .leading) {
							Text("Last seen device:")
							Text("\(String(describing: device))")
						}
					}
				}.padding(.top, 3.0)
#else
				//Different alignment for Mac
				HStack(alignment: .firstTextBaseline){
					TransportIcon(transportType: device.transportType)
					if device.isManualConnection && (device.longName != nil || device.shortName != nil) {
						Text("Last seen device: \(String(describing: device))")
					}
				}
#endif
			}
			Spacer()
			VStack {
				device.getSignalStrength().map {
					SignalStrengthIndicator(signalStrength: $0)
				}
			}
		}.padding([.bottom, .top])
			.confirmationDialog("Connecting to a new radio will clear all app data on the phone.", isPresented: $presentingSwitchPreferredPeripheral, titleVisibility: .visible) {
				Button("Connect to new radio?", role: .destructive) {
					Task {
						UserDefaults.preferredPeripheralId = device.id.uuidString
						UserDefaults.preferredPeripheralNum = 0
						if accessoryManager.allowDisconnect {
							try await accessoryManager.disconnect()
						}
						await MeshPackets.shared.clearCoreDataDatabase(includeRoutes: false)
						clearNotifications()
						
						try await accessoryManager.connect(to: device)
						
					}
				}
			}
	}
}

